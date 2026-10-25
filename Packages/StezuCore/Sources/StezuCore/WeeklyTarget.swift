import Foundation

/// Settings for the weekly target rule. Every value is a default, not a personal number.
public struct WeeklyTargetConfig: Sendable {
  /// Target rate of gain in lb/week. Must lie inside `targetRateBand`.
  public var targetRate: Double
  public var targetRateBand: ClosedRange<Double>
  /// Raise when the trend rate is more than this many lb/week under the target rate.
  public var underThreshold: Double
  /// Lower when the trend rate is more than this many lb/week over the target rate.
  public var overThreshold: Double
  /// kcal added on a raise. Must lie inside `raiseStepBand`.
  public var raiseStep: Double
  public var raiseStepBand: ClosedRange<Double>
  /// kcal taken off on a lower.
  public var lowerStep: Double
  /// The trend rate is the trend change over this many days, divided by `rateWindowDays / 7`.
  public var rateWindowDays: Int
  /// Fewer days than this since the first weigh-in gives insufficient data.
  public var minDaysOfData: Int
  /// Fewer weigh-in days than this in the 7 days ending on the read day gives insufficient data.
  public var minWeighInsInWeek: Int
  /// No change when the last change was fewer than this many days before the read day.
  public var minDaysBetweenChanges: Int
  /// The trend settings, including the calendar that decides which day a weigh-in belongs to.
  public var trend: TrendWeightConfig

  public init(
    targetRate: Double = 0.35,
    targetRateBand: ClosedRange<Double> = 0.25...0.5,
    underThreshold: Double = 0.15,
    overThreshold: Double = 0.25,
    raiseStep: Double = 100,
    raiseStepBand: ClosedRange<Double> = 100...150,
    lowerStep: Double = 100,
    rateWindowDays: Int = 21,
    minDaysOfData: Int = 21,
    minWeighInsInWeek: Int = 4,
    minDaysBetweenChanges: Int = 7,
    trend: TrendWeightConfig = .init()
  ) {
    self.targetRate = targetRate
    self.targetRateBand = targetRateBand
    self.underThreshold = underThreshold
    self.overThreshold = overThreshold
    self.raiseStep = raiseStep
    self.raiseStepBand = raiseStepBand
    self.lowerStep = lowerStep
    self.rateWindowDays = rateWindowDays
    self.minDaysOfData = minDaysOfData
    self.minWeighInsInWeek = minWeighInsInWeek
    self.minDaysBetweenChanges = minDaysBetweenChanges
    self.trend = trend
  }
}

/// The rule's verdict for one week. Every case leaves or moves the target by a known amount.
public struct WeeklyTargetDecision: Sendable, Equatable {
  public enum Action: Sendable, Equatable {
    case raise
    case lower
    case hold
    /// A change is due, but the target already changed within the last week.
    case alreadyChangedThisWeek
    /// Too few weigh-ins or too few days. The target is left alone.
    case insufficientData
  }

  public let asOf: Date
  public let action: Action
  public let previousTarget: Double
  /// The target to use from now on. Equal to `previousTarget` unless the action is raise or lower.
  public let newTarget: Double
  /// The 3-week trend rate in lb/week. Nil when there was too little data to compute it.
  public let trendRate: Double?
  public let reason: String
  public let confidence: Confidence
}

/// The weekly calorie target rule from SPEC.md.
public enum WeeklyTarget {
  /// The decision on `date` for a kcal target of `currentTarget`.
  /// `lastChange` is the day the target last moved, or nil if it never has.
  public static func evaluate(
    asOf date: Date, currentTarget: Double, weighIns: [WeighIn], lastChange: Date?,
    config: WeeklyTargetConfig = .init()
  ) -> WeeklyTargetDecision {
    precondition(config.targetRateBand.contains(config.targetRate), "target rate outside band")
    precondition(config.raiseStepBand.contains(config.raiseStep), "raise step outside band")
    let calendar = config.trend.calendar
    let end = calendar.startOfDay(for: date)
    let days = Set(
      weighIns.filter { $0.pounds.isFinite && $0.pounds > 0 }
        .map { calendar.startOfDay(for: $0.date) }
    ).filter { $0 <= end }

    func insufficient(_ reason: String) -> WeeklyTargetDecision {
      WeeklyTargetDecision(
        asOf: end, action: .insufficientData, previousTarget: currentTarget,
        newTarget: currentTarget, trendRate: nil, reason: reason,
        confidence: Confidence(level: .low, reason: reason))
    }

    let daysOfData = days.min().map { daysBetween($0, end, calendar) } ?? 0
    guard daysOfData >= config.minDaysOfData else {
      return insufficient(
        "\(daysOfData) days of weigh-in data; needs \(config.minDaysOfData). No change.")
    }
    let inWeek = days.filter { daysBetween($0, end, calendar) < 7 }.count
    guard inWeek >= config.minWeighInsInWeek else {
      return insufficient(
        "\(inWeek) weigh-ins in the last 7 days; needs \(config.minWeighInsInWeek). No change.")
    }
    guard
      let windowStart = calendar.date(byAdding: .day, value: -config.rateWindowDays, to: end),
      let startTrend = TrendWeight.estimate(
        asOf: windowStart, weighIns: weighIns, config: config.trend),
      let endTrend = TrendWeight.estimate(asOf: end, weighIns: weighIns, config: config.trend)
    else {
      return insufficient("No weigh-in on or before the start of the 3-week window. No change.")
    }

    let rate = (endTrend.trend - startTrend.trend) / (Double(config.rateWindowDays) / 7)
    let gap = rate - config.targetRate
    let rates = String(
      format: "Trend %.2f lb/week vs target %.2f lb/week", rate, config.targetRate)
    var action: WeeklyTargetDecision.Action
    var delta = 0.0
    var reason: String
    if gap < -config.underThreshold {
      (action, delta) = (.raise, config.raiseStep)
      reason = "\(rates): more than \(config.underThreshold) under, raise by \(Int(delta)) kcal."
    } else if gap > config.overThreshold {
      (action, delta) = (.lower, -config.lowerStep)
      reason = "\(rates): more than \(config.overThreshold) over, lower by \(Int(-delta)) kcal."
    } else {
      (action, reason) = (.hold, "\(rates): within the band, no change.")
    }
    if delta != 0, let last = lastChange,
      daysBetween(calendar.startOfDay(for: last), end, calendar) < config.minDaysBetweenChanges
    {
      (action, delta) = (.alreadyChangedThisWeek, 0)
      reason = "\(rates). The target already changed in the last week, no change."
    }

    let level = min(startTrend.confidence.level, endTrend.confidence.level)
    return WeeklyTargetDecision(
      asOf: end, action: action, previousTarget: currentTarget, newTarget: currentTarget + delta,
      trendRate: rate, reason: reason,
      confidence: Confidence(
        level: level,
        reason: "Trend confidence \(startTrend.confidence.level) 3 weeks ago, "
          + "\(endTrend.confidence.level) now"))
  }

  private static func daysBetween(_ from: Date, _ to: Date, _ calendar: Calendar) -> Int {
    calendar.dateComponents([.day], from: from, to: to).day!
  }
}
