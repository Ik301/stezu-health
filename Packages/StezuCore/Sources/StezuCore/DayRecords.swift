import Foundation

/// One thing recorded on a day and the app it came from (S-025).
public struct DayRecord: Sendable, Equatable {
  /// In the order the Day view lists them.
  public enum Kind: String, Sendable, CaseIterable {
    case weighIn = "Weigh-in"
    case meal = "Meal"
    case workout = "Workout"
    case sleep = "Sleep"
    case hrv = "HRV"
    case steps = "Steps"
  }

  /// What Stezu may change: its own weigh-ins, meals and sessions. Everything else is Health's
  /// and read-only.
  public enum Owner: Sendable, Equatable {
    case weighIn(Date)
    case meal(UUID)
    case session(Date)
    case health
  }

  public let kind: Kind
  public let time: Date
  /// The value: "170.6 lb", a meal's items and ranges, a session's sets; "--" when unknown.
  public let detail: String
  /// The app that wrote it ("Stezu", "Phone"); "Health" where the read carries no app.
  public let source: String
  public let owner: Owner

  public var isStezu: Bool { owner != .health }
}

public enum DayRecords {
  /// Everything on the day of `day`: weigh-ins from any app, logged meals, Stezu sessions and
  /// Health workouts (one entry when Finish wrote the session to Health), the night ending that
  /// day, each HRV reading and the day's steps. A read that throws is absent; nothing is 0.
  public static func load(
    _ day: Date, from store: any HealthStore, meals: [LoggedMeal], sessions: [WorkoutSession],
    calendar: Calendar = .current
  ) async -> [DayRecord] {
    let start = calendar.startOfDay(for: day)
    let span = DateInterval(start: start, end: start + 86_400)
    func read(_ type: HealthType) async -> [HealthSample] {
      ((try? await store.samples(of: type, since: start)) ?? []).filter { span.contains($0.date) }
    }
    var records: [DayRecord] = []
    for sample in await read(.bodyMass) {
      let own = sample.sourceBundleID == WeeklyWeight.stezuBundleID
      records.append(
        DayRecord(
          kind: .weighIn, time: sample.date,
          detail: sample.value.map { String(format: "%.1f lb", $0) } ?? "--",
          source: sample.sourceName, owner: own ? .weighIn(sample.date) : .health))
    }
    for meal in meals where span.contains(meal.loggedAt) {
      let names = meal.items.map(\.name).joined(separator: ", ")
      let kcal = FoodRange.text(.total(meal.items.map(\.kcal)), unit: "kcal")
      let protein = FoodRange.text(.total(meal.items.map(\.proteinG)), unit: "g protein")
      records.append(
        DayRecord(
          kind: .meal, time: meal.loggedAt, detail: "\(names): \(kcal), \(protein)",
          source: "Stezu", owner: .meal(meal.id)))
    }
    var starts: [Date] = []
    for session in sessions
    where span.contains(session.startedAt)
      && !starts.contains(session.startedAt)
    {
      starts.append(session.startedAt)
      let lines = session.exercises.map { log in
        log.exercise + " "
          + log.sets.map { "\($0.pounds.map { "\(Int($0)) lb" } ?? "bodyweight") x \($0.reps)" }
          .joined(separator: ", ")
      }
      records.append(
        DayRecord(
          kind: .workout, time: session.startedAt,
          detail: lines.isEmpty ? "--" : lines.joined(separator: "; "), source: "Stezu",
          owner: .session(session.startedAt)))
    }
    for workout in await read(.workout)
    where !starts.contains(where: { abs($0.timeIntervalSince(workout.date)) < 60 }) {
      records.append(
        DayRecord(
          kind: .workout, time: workout.date, detail: "--", source: workout.sourceName,
          owner: .health))
    }
    let intervals = (try? await store.sleepIntervals(since: start - 86_400)) ?? []
    if let asleep = SleepNights.nights(intervals, calendar: calendar)[start] {
      let detail = "\(Int(asleep / 3600))h \(Int(asleep / 60) % 60)m asleep"
      records.append(
        DayRecord(kind: .sleep, time: start, detail: detail, source: "Health", owner: .health))
    }
    for sample in await read(.heartRateVariability) {
      records.append(
        DayRecord(
          kind: .hrv, time: sample.date,
          detail: sample.value.map { "\(Int($0.rounded())) ms" } ?? "--",
          source: sample.sourceName, owner: .health))
    }
    let steps = try? await store.dailyValues(of: .stepCount, in: span)[start]
    if let steps {
      let names = Set(await read(.stepCount).map(\.sourceName)).sorted()
      records.append(
        DayRecord(
          kind: .steps, time: start, detail: "\(Int(steps.rounded()))",
          source: names.isEmpty ? "Health" : names.joined(separator: ", "), owner: .health))
    }
    let order = DayRecord.Kind.allCases
    return records.sorted {
      ($0.kind == $1.kind)
        ? ($0.time, $0.detail) < ($1.time, $1.detail)
        : order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)!
    }
  }
}
