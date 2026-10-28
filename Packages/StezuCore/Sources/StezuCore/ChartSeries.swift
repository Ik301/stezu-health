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

  /// A Sparkline's values: the current week's days, Monday to Sunday; a day without data stays
  /// nil (a dashed slot), never 0.
  public static func sparkline(_ history: MetricHistory) -> [Double?] {
    history.weeks.first?.days.map(\.value) ?? []
  }

  /// A week's CoverageDots: its days up to `now`, filled where there is data. For Workouts a
  /// dot is filled on a day with sets, since a rest day's 0 is data too.
  public static func coverage(_ week: MetricWeek, of metric: Metric, now: Date) -> [Bool] {
    week.days.filter { $0.day <= now }.map {
      $0.value.map { metric != .workouts || $0 > 0 } ?? false
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

  /// Working sets: a day's value is the sets of its Stezu sessions, a session in two stores
  /// (the same start within a second) counted once, and a week's is their total. A day up to
  /// `now` without a session is a rest day, a real 0, in a week with a session; a week without
  /// a session is absent, its days too (D-120).
  public static func workouts(
    _ sessions: [WorkoutSession], now: Date, calendar: Calendar = .current
  ) -> MetricHistory {
    var unique: [WorkoutSession] = []
    for session in sessions.sorted(by: { $0.startedAt < $1.startedAt })
    where !unique.contains(where: { abs($0.startedAt.timeIntervalSince(session.startedAt)) < 1 }) {
      unique.append(session)
    }
    let sets = Dictionary(grouping: unique) { calendar.startOfDay(for: $0.startedAt) }
      .mapValues { Double($0.reduce(0) { $0 + $1.workingSets }) }
    let current = WeeklyStats.week(containing: now, calendar: calendar).start
    let days = (-49..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: current) }
    let monday = { WeeklyStats.week(containing: $0, calendar: calendar).start }
    let trained = Set(sets.keys.map(monday))
    let daily = Dictionary(
      uniqueKeysWithValues: days.filter { $0 <= now && trained.contains(monday($0)) }.map {
        ($0, sets[$0] ?? 0)
      })
    return history(.workouts, daily: daily, now: now, sources: ["Stezu"], calendar: calendar) {
      week in
      let inWeek = unique.filter { week.contains($0.startedAt) }
      return WeeklyStat(
        value: Double(inWeek.reduce(0) { $0 + $1.workingSets }), coverage: inWeek.count,
        of: "sessions")
    }
  }
}
