import Foundation

/// One bar of WeekBars (S-042). `value` is nil for a week without data, drawn as a dashed slot
/// with "--", never as 0. An estimate (food) also has its low-to-high band; `value` is then the
/// band's midpoint. `coverage` counts the days (or samples) with data.
public struct WeekBar: Sendable, Equatable {
  public let start: Date
  public let value: Double?
  public let band: FoodRange?
  public let coverage: Int
}

public enum ChartSeries {
  /// A metric's 8 weeks as bars, oldest first, so the current week is last (on the right).
  public static func weekBars(_ history: MetricHistory) -> [WeekBar] {
    history.weeks.reversed().map {
      WeekBar(start: $0.start, value: $0.stat.value, band: nil, coverage: $0.stat.coverage)
    }
  }

  /// One nutrient's 8 weeks as bands, oldest first, each made as This week's Food row is: a
  /// day's low sums its items' lows and its high their highs, and a week's band is the mean of
  /// its logged days' lows and of their highs.
  public static func rangeBands(
    _ meals: [LoggedMeal], _ nutrient: KeyPath<WeeklyFood, WeeklyRange>, now: Date,
    calendar: Calendar = .current
  ) -> [WeekBar] {
    let current = WeeklyStats.week(containing: now, calendar: calendar).start
    return (0..<8).reversed().compactMap { back in
      guard let start = calendar.date(byAdding: .day, value: -7 * back, to: current) else {
        return nil
      }
      let week = DateInterval(start: start, duration: 7 * 86_400)
      let range = WeeklyIntake.food(meals, in: week, calendar: calendar)[keyPath: nutrient]
      return WeekBar(
        start: start, value: range.value.map { ($0.low + $0.high) / 2 }, band: range.value,
        coverage: range.coverage)
    }
  }
}

extension MetricHistory {
  /// Food's weeks and days for the detail list: a day's value is the midpoint of its kcal range
  /// and a week's the mean over its days with a known total.
  public static func food(_ meals: [LoggedMeal], now: Date, calendar: Calendar = .current)
    -> MetricHistory
  {
    let daily = Dictionary(grouping: meals) { calendar.startOfDay(for: $0.loggedAt) }
      .compactMapValues { FoodRange.total($0.flatMap(\.items).map(\.kcal)) }
      .mapValues { ($0.low + $0.high) / 2 }
    return history(.food, daily: daily, now: now, sources: ["Stezu"], calendar: calendar) {
      WeeklyStats.meanPerDay(daily, in: $0)
    }
  }
}
