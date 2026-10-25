import Foundation

/// One reading from the scale, in pounds.
public struct WeighIn: Sendable, Equatable {
  public let date: Date
  public let pounds: Double

  public init(date: Date, pounds: Double) {
    self.date = date
    self.pounds = pounds
  }
}

/// Settings for the trend. Every value is a default, not a personal number.
public struct TrendWeightConfig: Sendable {
  /// Smoothing per day, in (0, 1]. A gap of d days gives the new weigh-in 1 - (1 - alpha)^d.
  public var alpha: Double
  /// The calendar (and its time zone) that decides which day a weigh-in belongs to.
  public var calendar: Calendar
  /// Confidence looks at the weigh-in days in this many days, ending on the day it is read.
  public var confidenceWindowDays: Int
  /// High: at least this many weigh-in days in the window, and the last one recent enough.
  public var highMinWeighIns: Int
  public var highMaxDaysSinceLast: Int
  /// Medium: the same, with lower bars. Anything else is low.
  public var mediumMinWeighIns: Int
  public var mediumMaxDaysSinceLast: Int

  public init(
    alpha: Double = 0.1,
    calendar: Calendar = .current,
    confidenceWindowDays: Int = 14,
    highMinWeighIns: Int = 8,
    highMaxDaysSinceLast: Int = 3,
    mediumMinWeighIns: Int = 4,
    mediumMaxDaysSinceLast: Int = 7
  ) {
    self.alpha = alpha
    self.calendar = calendar
    self.confidenceWindowDays = confidenceWindowDays
    self.highMinWeighIns = highMinWeighIns
    self.highMaxDaysSinceLast = highMaxDaysSinceLast
    self.mediumMinWeighIns = mediumMinWeighIns
    self.mediumMaxDaysSinceLast = mediumMaxDaysSinceLast
  }
}

/// The trend on a day that has a weigh-in.
public struct TrendPoint: Sendable, Equatable {
  /// The start of the weigh-in's day in the config's calendar.
  public let day: Date
  /// The day's reading (the mean, if there was more than one).
  public let pounds: Double
  public let trend: Double
  /// Days since the previous weigh-in day. Nil for the first one, which seeds the trend.
  public let gapDays: Int?
  public let confidence: Confidence
}

/// The trend as read on any day, with or without a weigh-in that day.
public struct TrendEstimate: Sendable, Equatable {
  public let asOf: Date
  public let trend: Double
  public let lastWeighInDay: Date
  public let daysSinceLastWeighIn: Int
  public let confidence: Confidence
}

/// Trend weight: an EWMA over weigh-ins on irregular days.
public enum TrendWeight {
  /// One point per day with a valid weigh-in, oldest first. Empty when there are none.
  /// Days without a weigh-in get no point and do not move the trend.
  public static func series(_ weighIns: [WeighIn], config: TrendWeightConfig = .init())
    -> [TrendPoint]
  {
    precondition(config.alpha > 0 && config.alpha <= 1, "alpha must be in (0, 1]")
    let days = dailyReadings(weighIns, calendar: config.calendar)
    let dayIndexes = days.map { dayIndex($0.day, config.calendar) }
    var points: [TrendPoint] = []
    for (index, reading) in days.enumerated() {
      let trend: Double
      var gap: Int?
      if let previous = points.last {
        let d = dayIndexes[index] - dayIndexes[index - 1]
        let weight = 1 - pow(1 - config.alpha, Double(d))
        trend = previous.trend + weight * (reading.pounds - previous.trend)
        gap = d
      } else {
        trend = reading.pounds
      }
      let confidence = confidenceFor(
        dayIndexes: Array(dayIndexes[...index]), readOn: dayIndexes[index], config: config)
      points.append(
        TrendPoint(
          day: reading.day, pounds: reading.pounds, trend: trend, gapDays: gap,
          confidence: confidence))
    }
    return points
  }

  /// The trend as of a day. Nil when there is no weigh-in on or before that day.
  /// Between weigh-ins the trend holds its last value, and confidence drops as it ages.
  public static func estimate(
    asOf date: Date, weighIns: [WeighIn], config: TrendWeightConfig = .init()
  ) -> TrendEstimate? {
    let readOn = dayIndex(date, config.calendar)
    let points = series(weighIns, config: config)
      .filter { dayIndex($0.day, config.calendar) <= readOn }
    guard let last = points.last else { return nil }
    let indexes = points.map { dayIndex($0.day, config.calendar) }
    return TrendEstimate(
      asOf: config.calendar.startOfDay(for: date), trend: last.trend, lastWeighInDay: last.day,
      daysSinceLastWeighIn: readOn - indexes[indexes.count - 1],
      confidence: confidenceFor(dayIndexes: indexes, readOn: readOn, config: config))
  }

  /// Valid readings grouped by calendar day, averaged within a day, oldest first.
  private static func dailyReadings(_ weighIns: [WeighIn], calendar: Calendar)
    -> [(day: Date, pounds: Double)]
  {
    var byDay: [Date: [Double]] = [:]
    for weighIn in weighIns where weighIn.pounds.isFinite && weighIn.pounds > 0 {
      byDay[calendar.startOfDay(for: weighIn.date), default: []].append(weighIn.pounds)
    }
    return byDay.keys.sorted().map { day in
      let values = byDay[day]!
      return (day, values.reduce(0, +) / Double(values.count))
    }
  }

  /// Whole calendar days since a fixed reference, so gaps survive daylight-saving changes.
  private static func dayIndex(_ date: Date, _ calendar: Calendar) -> Int {
    let reference = calendar.startOfDay(for: Date(timeIntervalSince1970: 0))
    let day = calendar.startOfDay(for: date)
    return calendar.dateComponents([.day], from: reference, to: day).day!
  }

  private static func confidenceFor(dayIndexes: [Int], readOn: Int, config: TrendWeightConfig)
    -> Confidence
  {
    let windowStart = readOn - config.confidenceWindowDays + 1
    let count = dayIndexes.filter { $0 >= windowStart && $0 <= readOn }.count
    let since = readOn - (dayIndexes.last ?? readOn)
    let level: Confidence.Level
    if count >= config.highMinWeighIns && since <= config.highMaxDaysSinceLast {
      level = .high
    } else if count >= config.mediumMinWeighIns && since <= config.mediumMaxDaysSinceLast {
      level = .medium
    } else {
      level = .low
    }
    let noun = count == 1 ? "weigh-in" : "weigh-ins"
    let reason =
      "\(count) \(noun) in the last \(config.confidenceWindowDays) days; "
      + "last one \(since) \(since == 1 ? "day" : "days") ago"
    return Confidence(level: level, reason: reason)
  }
}
