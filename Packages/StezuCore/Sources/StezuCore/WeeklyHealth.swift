import Foundation

/// One metric over one Monday-to-Sunday week (S-022). `value` is nil when the week has no data,
/// so the row shows "--" beside its coverage (days, nights or readings), never 0.
public struct WeeklyStat: Sendable, Equatable {
  public let value: Double?
  public let coverage: Int
  public let confidence: Confidence

  init(value: Double?, coverage: Int, of unit: String) {
    (self.value, self.coverage) = (coverage > 0 ? value : nil, coverage)
    let level: Confidence.Level = coverage >= 5 ? .high : coverage >= 3 ? .medium : .low
    confidence =
      coverage > 0
      ? Confidence(level: level, reason: "\(coverage) \(unit)")
      : Confidence(level: .low, reason: HealthSources.deniedHint)
  }
}

/// A sleepAnalysis stage; raw values are HealthKit's category values. In bed and awake are not
/// time asleep.
public enum SleepStage: Int, Sendable {
  case inBed = 0
  case asleepUnspecified, awake, asleepCore, asleepDeep, asleepREM

  public var isAsleep: Bool { self != .inBed && self != .awake }
}

public typealias SleepInterval = (start: Date, end: Date, stage: SleepStage)

public enum SleepNights {
  /// Time asleep per night, keyed by the day the night ends on; a stage ending after 18:00
  /// counts toward the next day. Overlapping asleep stages (two apps, one night) count once.
  public static func nights(_ intervals: [SleepInterval], calendar: Calendar = .current)
    -> [Date: TimeInterval]
  {
    let asleep = intervals.filter { $0.stage.isAsleep && $0.end > $0.start }
    return Dictionary(grouping: asleep) { calendar.startOfDay(for: $0.end + 6 * 3600) }
      .mapValues { stages in
        var (total, reach) = (0.0, Date.distantPast)
        for stage in stages.sorted(by: { $0.start < $1.start }) where stage.end > reach {
          total += stage.end.timeIntervalSince(max(stage.start, reach))
          reach = stage.end
        }
        return total
      }
  }
}

public enum WeeklyStats {
  /// The Monday-to-Sunday week containing `now`.
  public static func week(containing now: Date, calendar: Calendar = .current) -> DateInterval {
    var calendar = calendar
    calendar.firstWeekday = 2
    return calendar.dateInterval(of: .weekOfYear, for: now)
      ?? DateInterval(start: now, duration: 7 * 86_400)
  }

  /// The mean of per-day values (steps' totals, resting heart rate's means, nights asleep) over
  /// the days of `week` that have one; coverage counts those days.
  public static func meanPerDay(
    _ days: [Date: Double], in week: DateInterval, of unit: String = "of 7 days with data"
  ) -> WeeklyStat {
    let values = days.filter { $0.key >= week.start && $0.key < week.end }.map(\.value)
    return WeeklyStat(value: mean(values), coverage: values.count, of: unit)
  }

  /// HRV: the median of every reading this week; coverage counts the readings.
  public static func median(_ samples: [HealthSample], in week: DateInterval) -> WeeklyStat {
    let values = samples.filter { $0.date >= week.start && $0.date < week.end }
      .compactMap(\.value).sorted()
    let median =
      values.isEmpty ? nil : (values[(values.count - 1) / 2] + values[values.count / 2]) / 2
    return WeeklyStat(value: median, coverage: values.count, of: "samples this week")
  }

  /// Sleep: the mean time asleep over the nights that end this week; coverage counts the nights.
  public static func sleep(
    _ intervals: [SleepInterval], in week: DateInterval, calendar: Calendar = .current
  ) -> WeeklyStat {
    meanPerDay(
      SleepNights.nights(intervals, calendar: calendar), in: week, of: "of 7 nights with data")
  }

  static func mean(_ values: [Double]) -> Double? {
    values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
  }
}

/// The overview's steps, sleep, HRV and resting heart rate for one week; sleep and HRV are
/// context only.
public struct WeeklyHealth: Sendable, Equatable {
  public let steps, sleep, hrv, restingHeartRate: WeeklyStat

  /// Reads the week containing `now`. A read that throws (or is denied) is absent.
  public static func load(from store: any HealthStore, now: Date, calendar: Calendar = .current)
    async -> WeeklyHealth
  {
    let week = WeeklyStats.week(containing: now, calendar: calendar)
    let steps = (try? await store.dailyValues(of: .stepCount, in: week)) ?? [:]
    let resting = (try? await store.dailyValues(of: .restingHeartRate, in: week)) ?? [:]
    // A night ending Monday morning starts on Sunday.
    let sleep = (try? await store.sleepIntervals(since: week.start - 86_400)) ?? []
    let hrv = (try? await store.samples(of: .heartRateVariability, since: week.start)) ?? []
    return WeeklyHealth(
      steps: WeeklyStats.meanPerDay(steps, in: week),
      sleep: WeeklyStats.sleep(sleep, in: week, calendar: calendar),
      hrv: WeeklyStats.median(hrv, in: week),
      restingHeartRate: WeeklyStats.meanPerDay(resting, in: week))
  }
}
