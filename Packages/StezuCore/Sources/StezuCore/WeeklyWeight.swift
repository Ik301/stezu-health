import Foundation

/// The Data overview's Weight row for one Monday-to-Sunday week (S-021). With no weigh-in this
/// week every value is nil and the row shows "--", never 0.
public struct WeekWeight: Sendable, Equatable {
  public let weekStart: Date
  /// The trend as of now.
  public let trend: Double?
  /// The trend now minus the trend at the end of last week (or this week's first weigh-in).
  public let change: Double?
  /// Days this week with a weigh-in, out of 7.
  public let daysWeighed: Int?
  public let confidence: Confidence
  /// The apps whose samples the trend uses.
  public let sources: [String]
}

public enum WeeklyWeight {
  /// Samples Health credits to Stezu. Only these count as weigh-ins by default, so a strap's
  /// static profile weight never moves the trend; Sources lists the other apps.
  public static let stezuBundleID = "com.ik301.stezuhealth"
  public static let noWeighInsReason = "No weigh-ins this week"
  /// How far back the trend reads.
  public static let historyDays = 90

  /// Weigh-ins from the given apps, with values.
  public static func weighIns(
    _ samples: [HealthSample], bundleIDs: Set<String> = [stezuBundleID]
  ) -> [WeighIn] {
    samples.filter { $0.type == .bodyMass && bundleIDs.contains($0.sourceBundleID ?? "") }
      .compactMap { sample in sample.value.map { WeighIn(date: sample.date, pounds: $0) } }
  }

  /// The week containing `now`, starting Monday.
  public static func week(of samples: [HealthSample], now: Date, calendar: Calendar = .current)
    -> WeekWeight
  {
    var calendar = calendar
    calendar.firstWeekday = 2
    let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
    let config = TrendWeightConfig(calendar: calendar)
    let all = weighIns(samples).filter { $0.date <= now }
    let thisWeek = all.filter { $0.date >= start }
    let days = Set(thisWeek.map { calendar.startOfDay(for: $0.date) }).count
    guard days > 0, let estimate = TrendWeight.estimate(asOf: now, weighIns: all, config: config)
    else {
      return WeekWeight(
        weekStart: start, trend: nil, change: nil, daysWeighed: nil,
        confidence: Confidence(level: .low, reason: noWeighInsReason), sources: [])
    }
    let before = TrendWeight.estimate(asOf: start - 1, weighIns: all, config: config)?.trend
    let firstThisWeek = TrendWeight.series(all, config: config).first { $0.day >= start }?.trend
    let baseline = before ?? firstThisWeek ?? estimate.trend
    let used = samples.filter { $0.type == .bodyMass && $0.sourceBundleID == stezuBundleID }
    return WeekWeight(
      weekStart: start, trend: estimate.trend, change: estimate.trend - baseline,
      daysWeighed: days, confidence: estimate.confidence,
      sources: Array(Set(used.map(\.sourceName))).sorted())
  }

  /// The stepper's start: the last Stezu weigh-in, else the last body-mass sample from any app,
  /// to 0.1 lb. Nil when Health has none.
  public static func prefill(from samples: [HealthSample]) -> Double? {
    let body = samples.filter { $0.type == .bodyMass && $0.value != nil }.sorted {
      $0.date < $1.date
    }
    let own = body.last { $0.sourceBundleID == stezuBundleID }
    return (own ?? body.last)?.value.map(tenths)
  }

  /// One tap: writes one body-mass sample, to 0.1 lb.
  public static func weighIn(pounds: Double, at date: Date, to store: any HealthStore)
    async throws
  {
    try await store.saveBodyMass(pounds: tenths(pounds), at: date)
  }

  /// The row and the prefill from Health. A read that throws (or is denied) is absent.
  public static func load(from store: any HealthStore, now: Date, calendar: Calendar = .current)
    async -> (week: WeekWeight, prefill: Double?)
  {
    let since = now.addingTimeInterval(-Double(historyDays) * 86_400)
    let samples = (try? await store.samples(of: .bodyMass, since: since)) ?? []
    return (week(of: samples, now: now, calendar: calendar), prefill(from: samples))
  }

  static func tenths(_ pounds: Double) -> Double { (pounds * 10).rounded() / 10 }
}
