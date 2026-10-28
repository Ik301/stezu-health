import Foundation

/// A lane of the Sleep screen's hypnogram (S-040). Unspecified asleep counts as Core.
public enum SleepLane: String, CaseIterable, Sendable {
  case awake = "Awake"
  case rem = "REM"
  case core = "Core"
  case deep = "Deep"

  static let stages: [SleepStage: SleepLane] = [
    .awake: .awake, .asleepREM: .rem, .asleepCore: .core, .asleepUnspecified: .core,
    .asleepDeep: .deep,
  ]
}

/// One night, named by its wake day; `asleep` is SleepNights'. Minutes count from the wake day's
/// midnight. A wake-up is awake between sleep onset and final wake, two apps' copies once.
public struct SleepNight: Sendable {
  public let day, bedtime, wake: Date
  public let asleep: TimeInterval
  public let bedMinutes, wakeMinutes: Double
  public let stages: [(lane: SleepLane, start: Date, end: Date)]
  public let totals: [SleepLane: TimeInterval]
  public let wakeUps: Int
  public let awakeAfterOnset: TimeInterval
}

/// Heart rate, breathing (low–high) and HRV (median) while asleep only; nil without a reading.
public struct Overnight: Sendable {
  public let heartRate, breathing: ClosedRange<Double>?
  public let hrv: Double?
  public let confidence: Confidence
}

/// The Sleep screen (S-040): 14 wake days ending today, their nights, S-037's usual night, the
/// window's median bedtime and wake, and its clock axis in whole hours (minutes from midnight).
public struct SleepDetail: Sendable {
  public let days: [Date]
  public let nights: [Date: SleepNight]
  public let overnight: [Date: Overnight]
  public let usual: TimeInterval?
  public let usualNights: Int
  public let usualBed, usualWake: Double?
  public let axis: ClosedRange<Double>
  public static let windowNights = 14

  public static func make(
    _ intervals: [SleepInterval], samples: [HealthSample], now: Date,
    calendar: Calendar = .current
  ) -> SleepDetail {
    let today = calendar.startOfDay(for: now)
    let days = (0..<windowNights).reversed().compactMap {
      calendar.date(byAdding: .day, value: -$0, to: today)
    }
    let asleep = SleepNights.nights(intervals, calendar: calendar)
    let groups = Dictionary(grouping: intervals) { calendar.startOfDay(for: $0.end + 6 * 3600) }
    var nights: [Date: SleepNight] = [:]
    for day in days {
      if let total = asleep[day] { nights[day] = night(groups[day] ?? [], day: day, asleep: total) }
    }
    let (bed, wake) = (nights.values.map(\.bedMinutes), nights.values.map(\.wakeMinutes))
    let low = ((bed.min() ?? -120) / 60).rounded(.down) * 60
    let high = ((wake.max() ?? 720) / 60).rounded(.up) * 60
    return SleepDetail(
      days: days, nights: nights, overnight: nights.mapValues { overnight($0, samples) },
      usual: SleepSummary.make(intervals, now: now, calendar: calendar).usual,
      usualNights: min(SleepSummary.usualNights, asleep.keys.filter { $0 <= today }.count),
      usualBed: WeeklyStats.median(bed), usualWake: WeeklyStats.median(wake), axis: low...high)
  }

  static func night(_ intervals: [SleepInterval], day: Date, asleep: TimeInterval) -> SleepNight? {
    let sleeping = intervals.filter { $0.stage.isAsleep && $0.end > $0.start }
    guard let onset = sleeping.map(\.start).min(), let wake = sleeping.map(\.end).max(),
      let bedtime = intervals.map(\.start).min()
    else { return nil }
    let stages = intervals.compactMap { s in SleepLane.stages[s.stage].map { ($0, s.start, s.end) }
    }
    let spans = { (lane: SleepLane) in merged(stages.filter { $0.0 == lane }.map { ($0.1, $0.2) }) }
    let woken = merged(spans(.awake).map { (max($0.0, onset), min($0.1, wake)) })
    let length = { (s: [(Date, Date)]) in s.reduce(0) { $0 + $1.1.timeIntervalSince($1.0) } }
    return SleepNight(
      day: day, bedtime: bedtime, wake: wake, asleep: asleep,
      bedMinutes: bedtime.timeIntervalSince(day) / 60,
      wakeMinutes: wake.timeIntervalSince(day) / 60,
      stages: stages,
      totals: Dictionary(uniqueKeysWithValues: SleepLane.allCases.map { ($0, length(spans($0))) }),
      wakeUps: woken.count, awakeAfterOnset: length(woken))
  }

  static func overnight(_ night: SleepNight, _ samples: [HealthSample]) -> Overnight {
    let asleep = night.stages.filter { $0.lane != .awake }
    let types: [HealthType] = [.heartRate, .respiratoryRate, .heartRateVariability]
    let inside = samples.filter { sample in
      sample.value != nil && types.contains(sample.type)
        && asleep.contains { $0.start <= sample.date && sample.date <= $0.end }
    }
    let values = { (type: HealthType) in inside.filter { $0.type == type }.compactMap(\.value) }
    let range = { (v: [Double]) in v.min().flatMap { low in v.max().map { low...$0 } } }
    let level: Confidence.Level = inside.count >= 20 ? .high : inside.count >= 5 ? .medium : .low
    return Overnight(
      heartRate: range(values(.heartRate)), breathing: range(values(.respiratoryRate)),
      hrv: WeeklyStats.median(values(.heartRateVariability)),
      confidence: Confidence(level: level, reason: "\(inside.count) readings while asleep"))
  }

  /// Overlapping or touching spans joined, oldest first.
  static func merged(_ spans: [(Date, Date)]) -> [(Date, Date)] {
    var joined: [(Date, Date)] = []
    for span in spans.filter({ $0.1 > $0.0 }).sorted(by: { $0.0 < $1.0 }) {
      if let last = joined.last, span.0 <= last.1 {
        joined[joined.count - 1].1 = max(last.1, span.1)
      } else {
        joined.append(span)
      }
    }
    return joined
  }

  /// Reads 60 days of nights (for the usual) and the window's overnight readings.
  public static func load(from store: any HealthStore, now: Date, calendar: Calendar = .current)
    async -> SleepDetail
  {
    let today = calendar.startOfDay(for: now)
    var samples: [HealthSample] = []
    for type in [HealthType.heartRate, .respiratoryRate, .heartRateVariability] {
      samples += (try? await store.samples(of: type, since: today - 15 * 86_400)) ?? []
    }
    let since = today - Double(SleepSummary.readDays + 1) * 86_400
    let intervals = (try? await store.sleepIntervals(since: since)) ?? []
    return make(intervals, samples: samples, now: now, calendar: calendar)
  }
}
