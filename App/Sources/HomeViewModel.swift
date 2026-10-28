import Foundation
import StezuCore

/// What the Home cards track (S-026, S-037): last night's sleep and this week's weight, today's
/// food, and this week's sessions, sets and next template. Each is nil until it exists (absent,
/// not zero). No targets (D-032).
struct HomeInputs: Sendable, Equatable {
  var sleep = SleepSummary.empty
  var weight: WeekWeight?
  var food: FoodDay?
  /// This week's sessions, Stezu and Health merged as on Data (S-023).
  var workouts: [WeekWorkout]?
  /// The name of the template the Workout area offers next.
  var nextTemplate: String?
  /// This week's working sets in Stezu sessions; nil without a session (S-042b).
  var sets: Int?
  var workoutInProgress = false

  /// Reads every input from the launch's services; a read that fails is absent.
  static func load(from environment: AppEnvironment) async -> HomeInputs {
    let now = environment.now()
    let week = WeeklyStats.week(containing: now)
    let meals = await environment.mealCaptures.logged() + environment.mealHistory
    let finished = FinishedWorkoutStore(storage: environment.storage).load()
    let stezu = environment.workoutHistory + finished.map(\.session)
    let health = (try? await environment.healthStore.samples(of: .workout, since: week.start)) ?? []
    let library = WorkoutTemplateStore(storage: environment.storage).load()
    return HomeInputs(
      sleep: await SleepSummary.load(from: environment.healthStore, now: now),
      weight: await WeeklyWeight.load(from: environment.weightHealth, now: now).week,
      food: FoodDay.on(now, meals: meals),
      workouts: WeeklyIntake.workouts(stezu: stezu, health: health, in: week),
      nextTemplate: WorkoutRotation.next(in: library, finished: finished)?.name,
      sets: MetricHistory.workouts(stezu, now: now).weeks.first?.stat.value.map { Int($0) },
      workoutInProgress: WorkoutSessionStore(storage: environment.storage).load() != nil)
  }
}

/// One Home card (design/system/components/GlanceCard): the area and its time frame, one number
/// with a small unit, and a detail row with a fact on each side. Missing data is "--", never 0.
struct HomeCard: Identifiable, Equatable, Sendable {
  /// A number and the small unit after it ("7" "h").
  struct Amount: Equatable, Sendable {
    let number: String
    var unit = ""
  }
  /// A detail fact: `value` in ink between muted words.
  struct Fact: Equatable, Sendable {
    var before = ""
    let value: String
    var after = ""
    var text: String { before + value + after }
  }

  let id: String
  let label: String
  let frame: String
  let amounts: [Amount]
  /// What VoiceOver reads for the number ("7 hours 12 minutes asleep").
  let spoken: String
  let left: Fact
  let right: Fact
  /// Data: the week's nights in hours, Monday first, nil where none is recorded.
  var bars: [Double?]? = nil
  /// The bars' index of today, Monday 0.
  var today = 6
  /// Workout: trained days from Monday up to today.
  var dots: [Bool]? = nil
  /// Confidence of the derived value; nil when the value is missing or not derived.
  var confidence: Confidence? = nil

  /// The number without its unit word; a duration keeps its h and m ("7h 20m", "3").
  var value: String {
    amounts.count > 1
      ? amounts.map { $0.number + $0.unit }.joined(separator: " ") : amounts.first?.number ?? ""
  }
  /// The whole card as one VoiceOver element.
  var accessibilityLabel: String { "\(label), \(frame), \(spoken), \(left.text), \(right.text)" }
}

/// Builds the Data, Food and Workout cards and picks the inverted one from an injected clock.
struct HomeViewModel: Sendable {
  static let missing = "--"

  /// Start hour and card id; a card stays inverted until the next start. Hours before the
  /// first start belong to the last entry. These are defaults, not personal numbers.
  static let defaultSchedule: [(hour: Int, cardID: String)] = [
    (5, "data"), (11, "food"), (16, "workout"), (20, "food"),
  ]

  var calendar: Calendar = .current
  var schedule: [(hour: Int, cardID: String)] = HomeViewModel.defaultSchedule
  var now: @Sendable () -> Date = { Date() }

  func cards(_ inputs: HomeInputs) -> [HomeCard] {
    [dataCard(inputs), foodCard(inputs), workoutCard(inputs)]
  }

  /// The id of the "do this now" card: Workout while a workout is in progress, otherwise the
  /// card for the clock's current hour.
  func invertedCardID(workoutInProgress: Bool = false) -> String? {
    if workoutInProgress { return "workout" }
    let hour = calendar.component(.hour, from: now())
    let sorted = schedule.sorted { $0.hour < $1.hour }
    return (sorted.last { $0.hour <= hour } ?? sorted.last)?.cardID
  }

  /// Last night's time asleep with the week's nights as bars; the usual night and the week's
  /// trend weight below (D-097).
  private func dataCard(_ inputs: HomeInputs) -> HomeCard {
    let sleep = inputs.sleep
    let minutes = sleep.lastNight.map { Int(($0 / 60).rounded()) }
    let weight = inputs.weight?.trend.map { String(format: "%.1f lb", $0) }
    return HomeCard(
      id: "data", label: "Data", frame: "Last night",
      amounts: minutes.map {
        [HomeCard.Amount(number: "\($0 / 60)", unit: "h"), .init(number: "\($0 % 60)", unit: "m")]
      } ?? [HomeCard.Amount(number: Self.missing)],
      spoken: minutes.map {
        "\(Self.count($0 / 60, "hour")) \(Self.count($0 % 60, "minute")) asleep"
      } ?? Self.missing,
      left: .init(before: "Usual ", value: sleep.usual.map(Self.duration) ?? Self.missing),
      right: .init(before: "Weight ", value: weight ?? Self.missing),
      bars: sleep.week, today: (calendar.component(.weekday, from: now()) + 5) % 7,
      confidence: minutes == nil ? nil : sleep.confidence)
  }

  /// Today's kcal range, with the protein range and the meal count below it.
  private func foodCard(_ inputs: HomeInputs) -> HomeCard {
    let day = inputs.food
    let kcal = day?.kcal.map(Self.range) ?? Self.missing
    let meals = day?.mealCount
    return HomeCard(
      id: "food", label: "Food", frame: "Today", amounts: [.init(number: kcal, unit: "kcal")],
      spoken: "\(kcal) kcal",
      left: .init(value: "\(day?.proteinG.map(Self.range) ?? Self.missing) g", after: " protein"),
      right: .init(
        value: meals.map(String.init) ?? Self.missing, after: meals == 1 ? " meal" : " meals"),
      confidence: day?.kcal == nil ? nil : day?.confidence)
  }

  /// Sessions this week with the trained days as dots; the next template and the week's
  /// working sets below.
  private func workoutCard(_ inputs: HomeInputs) -> HomeCard {
    let sessions = inputs.workouts.flatMap { $0.isEmpty ? nil : $0 }
    let confidence = sessions.map { all in
      let stezu = all.filter { $0.source == .stezu }.count
      return Confidence(
        level: .high, reason: "\(stezu) from Stezu, \(all.count - stezu) from Health")
    }
    let today = now()
    let monday = WeeklyStats.week(containing: today, calendar: calendar).start
    let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
      .filter { $0 <= today }
    let trained = days.map { day in
      sessions?.contains { calendar.isDate($0.start, inSameDayAs: day) } ?? false
    }
    let names = zip(days, trained).filter { $0.1 }.map {
      calendar.shortWeekdaySymbols[calendar.component(.weekday, from: $0.0) - 1]
    }
    let count = sessions.map { String($0.count) } ?? Self.missing
    let unit = sessions?.count == 1 ? "session" : "sessions"
    return HomeCard(
      id: "workout", label: "Workout", frame: "This week",
      amounts: [.init(number: count, unit: unit)],
      spoken: "\(count) \(unit)" + (names.isEmpty ? "" : " (\(names.joined(separator: ", ")))"),
      left: .init(before: "Next: ", value: inputs.nextTemplate ?? Self.missing),
      right: .init(
        value: inputs.sets.map(String.init) ?? Self.missing,
        after: inputs.sets == 1 ? " set" : " sets"),
      dots: trained, confidence: confidence)
  }

  /// "1,080–1,440": whole numbers with an en dash, grouped as in en_US whatever the locale.
  private static func range(_ range: FoodRange) -> String {
    let format = { (value: Double) in
      Int(value.rounded()).formatted(.number.locale(Locale(identifier: "en_US")))
    }
    return "\(format(range.low))–\(format(range.high))"
  }

  /// "7h 20m".
  private static func duration(_ seconds: TimeInterval) -> String {
    let minutes = Int((seconds / 60).rounded())
    return "\(minutes / 60)h \(minutes % 60)m"
  }

  private static func count(_ n: Int, _ noun: String) -> String {
    "\(n) \(noun)\(n == 1 ? "" : "s")"
  }
}
