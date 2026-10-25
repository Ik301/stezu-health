import Foundation

/// The v1 Health types the one Connect sheet asks for (SPEC, Data sources); Sources shows one row
/// per case. The raw value is the row title and the case name is the accessibility id stem.
public enum HealthType: String, CaseIterable, Sendable {
  case bodyMass = "Weight"
  case stepCount = "Steps"
  case heartRate = "Heart rate"
  case heartRateVariability = "HRV"
  case restingHeartRate = "Resting heart rate"
  case sleepAnalysis = "Sleep"
  case dietaryEnergy = "Energy eaten"
  case dietaryProtein = "Protein"
  case workout = "Workouts"
}

/// One sample's date and the app that wrote it. Values come with the stories that read them.
public struct HealthSample: Sendable, Equatable {
  public let type: HealthType
  public let date: Date
  public let sourceName: String
  public let sourceBundleID: String?

  public init(type: HealthType, date: Date, sourceName: String, sourceBundleID: String? = nil) {
    (self.type, self.date, self.sourceName, self.sourceBundleID) =
      (type, date, sourceName, sourceBundleID)
  }
}

/// One Sources row. HealthKit hides denied reads, so "no samples" and "no access" look the same:
/// both are absent, with the hint, never a count of 0.
public struct HealthTypeSummary: Sendable {
  public let type: HealthType
  /// The newest sample ever read; nil when absent.
  public let lastSampleDate: Date?
  /// Apps that wrote samples in the window with their sample counts, most samples first.
  public let recentSources: [(name: String, count: Int)]
  public let confidence: Confidence

  public var isPresent: Bool { lastSampleDate != nil }
  /// Samples in the window; nil when the type is absent.
  public var recentSampleCount: Int? { isPresent ? recentSources.map(\.count).reduce(0, +) : nil }
}

public enum HealthSources {
  /// Where to turn a denied read back on.
  public static let deniedHint = "No data, or read access is off: Health app, profile, Apps, Stezu."

  /// Builds a row from the newest sample date and the samples of the last `days` days.
  public static func summarize(
    type: HealthType, latest: Date?, recent: [HealthSample], now: Date, days: Int = 7
  ) -> HealthTypeSummary {
    let start = now.addingTimeInterval(-Double(days) * 86_400)
    let window = recent.filter { $0.type == type && $0.date >= start && $0.date <= now }
    let last = ([latest].compactMap { $0 } + window.map(\.date)).max()
    let sources = Dictionary(grouping: window, by: \.sourceName)
      .map { (name: $0.key, count: $0.value.count) }
      .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
    let confidence =
      last == nil
      ? Confidence(level: .low, reason: deniedHint)
      : Confidence(level: .high, reason: "\(window.count) samples in \(days) days")
    return HealthTypeSummary(
      type: type, lastSampleDate: last, recentSources: sources, confidence: confidence)
  }

  /// One row per v1 type. A read that throws counts as absent.
  public static func load(from store: any HealthStore, now: Date = Date(), days: Int = 7) async
    -> [HealthTypeSummary]
  {
    var rows: [HealthTypeSummary] = []
    for type in HealthType.allCases {
      let latest = try? await store.latestSampleDate(of: type)
      let since = now.addingTimeInterval(-Double(days) * 86_400)
      let recent = (try? await store.samples(of: type, since: since)) ?? []
      rows.append(summarize(type: type, latest: latest, recent: recent, now: now, days: days))
    }
    return rows
  }
}
