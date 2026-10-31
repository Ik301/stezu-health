import Foundation

/// Home's Data card (S-037): last night's time asleep, this week's nights and the usual night,
/// all from `SleepNights`, the code behind the Data screen's Sleep row. Every value is nil when
/// no night is recorded (absent, not 0). Context only: no target or score (D-032). Since S-051
/// Home, This week's Sleep row and the Sleep screen take last night and the week's mean from
/// here, and MetricHistory's sleep weeks use `weekMean` too, so the numbers cannot drift.
public struct SleepSummary: Sendable, Equatable {
  /// Time asleep in the night ending today.
  public let lastNight: TimeInterval?
  /// The median of the most recent recorded nights (up to `usualNights`) ending today or before.
  public let usual: TimeInterval?
  /// Monday to Sunday of the week containing now, in hours; nil on a night without data.
  public let week: [Double?]
  /// How far `usual` can be trusted: the number of nights it is the median of.
  public let confidence: Confidence?
  /// The mean time asleep over this week's recorded nights; coverage counts them.
  public let weekMean: WeeklyStat

  /// The most nights the usual night is the median of.
  public static let usualNights = 30
  /// How far back Home reads sleep, so 30 recorded nights can be found among missing ones.
  public static let readDays = 60

  public static let empty = SleepSummary(
    lastNight: nil, usual: nil, week: Array(repeating: nil, count: 7), confidence: nil,
    weekMean: weekMean([:], in: DateInterval()))

  public static func make(
    _ intervals: [SleepInterval], now: Date, calendar: Calendar = .current
  ) -> SleepSummary {
    let nights = SleepNights.nights(intervals, calendar: calendar)
    let today = calendar.startOfDay(for: now)
    let recent = nights.filter { $0.key <= today }.sorted { $0.key > $1.key }
      .prefix(usualNights).map(\.value)
    let monday = WeeklyStats.week(containing: now, calendar: calendar).start
    let week = (0..<7).map { offset in
      calendar.date(byAdding: .day, value: offset, to: monday).flatMap { nights[$0] }
        .map { $0 / 3600 }
    }
    let level: Confidence.Level = recent.count >= 14 ? .high : recent.count >= 5 ? .medium : .low
    return SleepSummary(
      lastNight: nights[today], usual: WeeklyStats.median(Array(recent)), week: week,
      confidence: recent.isEmpty
        ? nil : Confidence(level: level, reason: "median of \(recent.count) nights"),
      weekMean: weekMean(nights, in: WeeklyStats.week(containing: now, calendar: calendar)))
  }

  /// "6h 15m" to the nearest minute, "--" when absent; every sleep number on Home, This week
  /// and the Sleep screen is written by it.
  public static func text(_ seconds: TimeInterval?) -> String {
    guard let seconds else { return "--" }
    let minutes = Int((seconds / 60).rounded())
    return "\(minutes / 60)h \(minutes % 60)m"
  }

  /// The mean time asleep over the nights (keyed by wake day) that end in `week`.
  public static func weekMean(_ nights: [Date: TimeInterval], in week: DateInterval) -> WeeklyStat {
    WeeklyStats.meanPerDay(nights, in: week, of: "of 7 nights with data")
  }

  /// Reads the nights from Health; a read that throws (or is denied) is absent.
  public static func load(from store: any HealthStore, now: Date, calendar: Calendar = .current)
    async -> SleepSummary
  {
    let since = calendar.startOfDay(for: now) - Double(readDays + 1) * 86_400
    let intervals = (try? await store.sleepIntervals(since: since)) ?? []
    return make(intervals, now: now, calendar: calendar)
  }
}
