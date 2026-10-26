import Foundation

/// A weekly mean that stays a range (S-023): the mean of each day's low and of each day's high.
/// `value` is nil when no day has a known total, so the row shows "--", never 0.
public struct WeeklyRange: Sendable, Equatable {
  public let value: FoodRange?
  /// Logged days whose total is known; they are the days averaged.
  public let coverage: Int
  public let confidence: Confidence
}

/// This week's logged food: mean kcal and protein per logged day, and how many days were logged.
public struct WeeklyFood: Sendable, Equatable {
  public let kcal, protein: WeeklyRange
  /// Days of the week with at least one logged meal.
  public let loggedDays: Int
}

/// One session of the week and where it came from: Stezu's log, or another app via Health.
public struct WeekWorkout: Sendable, Equatable {
  public enum Source: String, Sendable {
    case stezu = "Stezu"
    case health = "Health"
  }
  public let start: Date
  public let source: Source
  /// "n sets" for a Stezu session; the writing app's name for a Health workout.
  public let detail: String

  public init(start: Date, source: Source, detail: String) {
    (self.start, self.source, self.detail) = (start, source, detail)
  }
}

public enum WeeklyIntake {
  /// Each logged day's total is its meals' lows summed and highs summed; the week's range is the
  /// mean of those totals over the logged days. A day with an item of unknown range has no known
  /// total, so it counts as logged but is left out of the mean (absent is not zero).
  public static func food(
    _ meals: [LoggedMeal], in week: DateInterval, calendar: Calendar = .current
  ) -> WeeklyFood {
    let days = Dictionary(grouping: meals.filter { week.contains($0.loggedAt) }) {
      calendar.startOfDay(for: $0.loggedAt)
    }
    func mean(_ nutrient: (MatchedItem) -> FoodRange?) -> WeeklyRange {
      let totals = days.values.compactMap { FoodRange.total($0.flatMap(\.items).map(nutrient)) }
      let count = Double(totals.count)
      let value =
        totals.isEmpty
        ? nil
        : FoodRange(
          low: totals.map(\.low).reduce(0, +) / count,
          high: totals.map(\.high).reduce(0, +) / count)
      let level: Confidence.Level = totals.count >= 5 ? .high : totals.count >= 3 ? .medium : .low
      let reason =
        totals.count == days.count
        ? "logged \(days.count) of 7 days"
        : "logged \(days.count) of 7 days, \(days.count - totals.count) with an unknown item"
      return WeeklyRange(
        value: value, coverage: totals.count,
        confidence: Confidence(
          level: totals.isEmpty ? .low : level, reason: reason))
    }
    return WeeklyFood(kcal: mean(\.kcal), protein: mean(\.proteinG), loggedDays: days.count)
  }

  /// This week's sessions, newest first. A Health workout starting within `tolerance` of a Stezu
  /// session is that session written back by Finish (or the same session from another app), so
  /// only the Stezu entry is kept; Stezu sessions repeated across stores count once.
  public static func workouts(
    stezu: [WorkoutSession], health: [HealthSample], in week: DateInterval,
    tolerance: TimeInterval = 60
  ) -> [WeekWorkout] {
    var merged: [WeekWorkout] = []
    for session in stezu.sorted(by: { $0.startedAt < $1.startedAt })
    where week.contains(session.startedAt)
      && !merged.contains(where: { abs($0.start.timeIntervalSince(session.startedAt)) < 1 })
    {
      let sets = session.workingSets
      merged.append(
        WeekWorkout(
          start: session.startedAt, source: .stezu, detail: "\(sets) set\(sets == 1 ? "" : "s")"))
    }
    for sample in health where sample.type == .workout && week.contains(sample.date) {
      guard !merged.contains(where: { abs($0.start.timeIntervalSince(sample.date)) < tolerance })
      else { continue }
      merged.append(WeekWorkout(start: sample.date, source: .health, detail: sample.sourceName))
    }
    return merged.sorted { $0.start > $1.start }
  }
}
