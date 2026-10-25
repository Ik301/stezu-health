import Foundation

/// One logged food entry, in kcal. A day's intake is the sum of its entries.
public struct IntakeEntry: Sendable, Equatable {
  public let date: Date
  public let kcal: Double

  public init(date: Date, kcal: Double) {
    self.date = date
    self.kcal = kcal
  }
}

/// Settings for the expenditure estimate. Every value is a default, not a personal number.
public struct ExpenditureConfig: Sendable {
  /// The window, in days, ending on the day the estimate is read.
  public var windowDays: Int
  public var kcalPerPound: Double
  /// A day is partial when its intake is under this fraction of its week's median.
  public var partialFraction: Double
  /// Fewer full logged days than this in the window gives insufficient data.
  public var minIncludedDays: Int
  /// Intake confidence: high with at least this many full days, medium with the minimum.
  public var highMinIncludedDays: Int
  /// The trend settings, including the calendar that decides which day an entry belongs to.
  public var trend: TrendWeightConfig

  public init(
    windowDays: Int = 21,
    kcalPerPound: Double = 3500,
    partialFraction: Double = 0.5,
    minIncludedDays: Int = 14,
    highMinIncludedDays: Int = 18,
    trend: TrendWeightConfig = .init()
  ) {
    self.windowDays = windowDays
    self.kcalPerPound = kcalPerPound
    self.partialFraction = partialFraction
    self.minIncludedDays = minIncludedDays
    self.highMinIncludedDays = highMinIncludedDays
    self.trend = trend
  }
}

public struct ExpenditureEstimate: Sendable, Equatable {
  public let asOf: Date
  /// Estimated expenditure, kcal per day.
  public let kcalPerDay: Double
  /// Mean intake over the full (non-partial) logged days in the window.
  public let meanIntake: Double
  /// Trend at the end of the window minus the trend the day before it starts, in pounds.
  public let trendChange: Double
  public let includedDays: Int
  public let partialDays: Int
  public let confidence: Confidence
}

public enum ExpenditureResult: Sendable, Equatable {
  case estimate(ExpenditureEstimate)
  /// Not enough intake or trend data. The reason is shown in place of a number.
  case insufficientData(reason: String)

  public var estimate: ExpenditureEstimate? {
    if case .estimate(let value) = self { return value }
    return nil
  }
}

/// Expenditure: mean intake minus the energy stored or released by the trend change.
public enum Expenditure {
  /// The estimate over the window ending on `date`.
  /// Days with no logged intake are absent and do not count as 0.
  public static func estimate(
    asOf date: Date, intake: [IntakeEntry], weighIns: [WeighIn],
    config: ExpenditureConfig = .init()
  ) -> ExpenditureResult {
    let calendar = config.trend.calendar
    let end = calendar.startOfDay(for: date)
    guard
      let windowStart = calendar.date(byAdding: .day, value: -(config.windowDays - 1), to: end),
      let beforeStart = calendar.date(byAdding: .day, value: -1, to: windowStart)
    else { return .insufficientData(reason: "Could not compute the window dates") }

    // Daily totals inside the window, keyed by day offset from the window start.
    var totals: [Int: Double] = [:]
    for entry in intake where entry.kcal.isFinite && entry.kcal > 0 {
      let day = calendar.startOfDay(for: entry.date)
      guard let offset = calendar.dateComponents([.day], from: windowStart, to: day).day,
        offset >= 0, offset < config.windowDays
      else { continue }
      totals[offset, default: 0] += entry.kcal
    }

    // Weeks are 7-day blocks counted from the window start.
    var byWeek: [Int: [Double]] = [:]
    for (offset, kcal) in totals { byWeek[offset / 7, default: []].append(kcal) }
    let medians = byWeek.mapValues(median)
    let full = totals.filter { offset, kcal in kcal >= config.partialFraction * medians[offset / 7]!
    }
    let partialDays = totals.count - full.count

    guard full.count >= config.minIncludedDays else {
      return .insufficientData(
        reason: "\(full.count) full intake days in the last \(config.windowDays); "
          + "needs \(config.minIncludedDays)")
    }
    guard
      let startTrend = TrendWeight.estimate(
        asOf: beforeStart, weighIns: weighIns, config: config.trend),
      let endTrend = TrendWeight.estimate(asOf: end, weighIns: weighIns, config: config.trend)
    else {
      return .insufficientData(reason: "No weigh-in on or before the start of the window")
    }

    let meanIntake = full.values.reduce(0, +) / Double(full.count)
    let trendChange = endTrend.trend - startTrend.trend
    let kcalPerDay = meanIntake - trendChange * config.kcalPerPound / Double(config.windowDays)

    let intakeLevel: Confidence.Level = full.count >= config.highMinIncludedDays ? .high : .medium
    let level = min(intakeLevel, startTrend.confidence.level, endTrend.confidence.level)
    let reason =
      "\(full.count) full intake days (\(partialDays) partial excluded) in the last "
      + "\(config.windowDays); trend confidence \(startTrend.confidence.level) at the start, "
      + "\(endTrend.confidence.level) at the end"
    return .estimate(
      ExpenditureEstimate(
        asOf: end, kcalPerDay: kcalPerDay, meanIntake: meanIntake, trendChange: trendChange,
        includedDays: full.count, partialDays: partialDays,
        confidence: Confidence(level: level, reason: reason)))
  }

  private static func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let mid = sorted.count / 2
    return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
  }
}
