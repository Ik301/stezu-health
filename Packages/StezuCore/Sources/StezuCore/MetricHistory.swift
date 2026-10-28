import Foundation

/// A metric on the Data overview. Each one opens the same detail (S-024, S-042). Breathing's
/// raw value is its overview row's id.
public enum Metric: String, CaseIterable, Sendable, Identifiable {
  case weight, steps, sleep, hrv, restingHR, food, workouts
  case breathing = "respiratory"

  public var id: String { rawValue }

  /// How a week's value is made, shown under the weeks.
  public var note: String {
    switch self {
    case .weight:
      "Each week shows the trend at its last weigh-in. The trend smooths Stezu weigh-ins; a "
        + "longer gap moves it further. Coverage counts days with a weigh-in."
    case .steps: "Mean steps per day over the days with data. Health merges overlapping apps."
    case .sleep: "Mean time asleep over the nights ending in the week. Context only."
    case .hrv: "Median of every reading in the week; a day shows its own median. Context only."
    case .restingHR: "Mean of each day's resting heart rate over the days with data."
    case .food:
      "Mean of the logged days. A day's range adds its meals' lows and highs; a day with an "
        + "unknown item is left out."
    case .breathing: "Median of every reading of the nights ending in the week. Context only."
    case .workouts:
      "Working sets: every logged set of a Stezu session, added up over the week. A day "
        + "without a session is a rest day, 0."
    }
  }
}

/// One day of a week; `value` is nil on a day without data, shown as "--".
public struct MetricDay: Sendable, Equatable {
  public let day: Date
  public let value: Double?
}

public struct MetricWeek: Sendable, Equatable {
  public let start: Date
  public let stat: WeeklyStat
  /// Monday to Sunday.
  public let days: [MetricDay]
}

/// A metric's last 8 Monday-to-Sunday weeks, newest first, with the apps behind them.
public struct MetricHistory: Sendable, Equatable {
  public let metric: Metric
  /// Newest first; the first is the week containing now.
  public let weeks: [MetricWeek]
  /// The apps the values come from; empty when the read carries none (sleep).
  public let sources: [String]
  /// Weight only: the weigh-in days in the 8 weeks with their trend, oldest first.
  public let trend: [TrendPoint]

  /// Splits per-day values (keyed by day start) into the 8 weeks ending with the week containing
  /// `now`; `stat` makes each week's value and coverage.
  public static func history(
    _ metric: Metric, daily: [Date: Double], now: Date, sources: [String] = [],
    trend: [TrendPoint] = [], calendar: Calendar = .current, stat: (DateInterval) -> WeeklyStat
  ) -> MetricHistory {
    let current = WeeklyStats.week(containing: now, calendar: calendar).start
    let weeks = (0..<8).map { back in
      let days = (0..<8).compactMap {
        calendar.date(byAdding: .day, value: $0 - 7 * back, to: current)
      }
      let week = DateInterval(start: days[0], end: days[7])
      return MetricWeek(
        start: days[0], stat: stat(week),
        days: days.dropLast().map { MetricDay(day: $0, value: daily[$0]) })
    }
    return MetricHistory(metric: metric, weeks: weeks, sources: sources, trend: trend)
  }

  /// Reads the 8 weeks from Health. A read that throws (or is denied) is absent.
  public static func load(
    _ metric: Metric, from store: any HealthStore, now: Date, calendar: Calendar = .current
  ) async -> MetricHistory {
    let current = WeeklyStats.week(containing: now, calendar: calendar)
    let first = calendar.date(byAdding: .day, value: -49, to: current.start) ?? current.start
    let span = DateInterval(start: first, end: current.end)
    let names = { (samples: [HealthSample]) in Array(Set(samples.map(\.sourceName))).sorted() }
    switch metric {
    case .weight:
      // The trend needs weigh-ins from before the first week to settle.
      let since = first - Double(WeeklyWeight.historyDays) * 86_400
      let samples = (try? await store.samples(of: .bodyMass, since: since)) ?? []
      let own = WeeklyWeight.weighIns(samples).filter { $0.date <= now }
      let series = TrendWeight.series(own, config: TrendWeightConfig(calendar: calendar))
      let daily = Dictionary(series.map { ($0.day, $0.pounds) }) { first, _ in first }
      let used = samples.filter { $0.sourceBundleID == WeeklyWeight.stezuBundleID }
      return history(
        metric, daily: daily, now: now, sources: names(used),
        trend: series.filter { $0.day >= first }, calendar: calendar
      ) { week in
        let inWeek = series.filter { $0.day >= week.start && $0.day < week.end }
        return WeeklyStat(value: inWeek.last?.trend, coverage: inWeek.count, of: "weigh-in days")
      }
    case .steps, .restingHR:
      let type: HealthType = metric == .steps ? .stepCount : .restingHeartRate
      let daily = (try? await store.dailyValues(of: type, in: span)) ?? [:]
      let samples = (try? await store.samples(of: type, since: first)) ?? []
      return history(metric, daily: daily, now: now, sources: names(samples), calendar: calendar) {
        WeeklyStats.meanPerDay(daily, in: $0)
      }
    case .sleep:
      // A night ending on the first Monday starts the Sunday before.
      let intervals = (try? await store.sleepIntervals(since: first - 86_400)) ?? []
      let nights = SleepNights.nights(intervals, calendar: calendar)
      return history(metric, daily: nights, now: now, calendar: calendar) {
        WeeklyStats.meanPerDay(nights, in: $0, of: "of 7 nights with data")
      }
    case .hrv:
      let samples = (try? await store.samples(of: .heartRateVariability, since: first)) ?? []
      let daily = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.date) }
        .compactMapValues { WeeklyStats.median($0, in: span).value }
      return history(metric, daily: daily, now: now, sources: names(samples), calendar: calendar) {
        WeeklyStats.median(samples, in: $0)
      }
    case .breathing:
      let samples = (try? await store.samples(of: .respiratoryRate, since: first - 86_400)) ?? []
      let nights = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.date + 6 * 3600) }
        .compactMapValues { WeeklyStats.median($0.compactMap(\.value)) }
      return history(metric, daily: nights, now: now, sources: names(samples), calendar: calendar) {
        WeeklyStats.nightlyMedian(samples, in: $0, calendar: calendar)
      }
    case .food, .workouts:
      // Logged meals and sessions are on the phone: see MetricHistory.food and .workouts.
      return history(metric, daily: [:], now: now, calendar: calendar) {
        WeeklyStats.meanPerDay([:], in: $0)
      }
    }
  }
}
