import Foundation

/// The protein floor flag: is the rolling mean of daily protein under a floor?
/// Uses the low end of each meal's estimate, so the flag errs toward eating more.
public enum ProteinFloor {
  /// One logged meal's protein estimate, a range in grams.
  public struct Meal: Sendable, Equatable {
    public let date: Date
    public let proteinLowGrams: Double
    public let proteinHighGrams: Double

    public init(date: Date, proteinLowGrams: Double, proteinHighGrams: Double) {
      self.date = date
      self.proteinLowGrams = proteinLowGrams
      self.proteinHighGrams = proteinHighGrams
    }
  }

  /// Settings for the check. The floor has no default: it is set on the device.
  public struct Config: Sendable {
    /// Grams per day. The mean of daily low ends under this is flagged.
    public var floorGrams: Double
    /// The calendar (and its time zone) that decides which day a meal belongs to.
    public var calendar: Calendar
    /// Days in the rolling window, ending on the day read. Every one must have logged food.
    public var windowDays: Int
    /// High confidence needs at least this many meals on every day of the window.
    public var highMinMealsPerDay: Int

    public init(
      floorGrams: Double, calendar: Calendar = .current, windowDays: Int = 3,
      highMinMealsPerDay: Int = 2
    ) {
      self.floorGrams = floorGrams
      self.calendar = calendar
      self.windowDays = windowDays
      self.highMinMealsPerDay = highMinMealsPerDay
    }
  }

  /// A check over a full window.
  public struct Check: Sendable, Equatable {
    public let asOf: Date
    /// Start of the first day in the window.
    public let windowStart: Date
    /// Sum of meal low ends per day, oldest first.
    public let dailyLowGrams: [Double]
    public let meanLowGrams: Double
    /// Context only; the flag never reads it.
    public let meanHighGrams: Double
    public let floorGrams: Double
    public let isUnderFloor: Bool
    public let confidence: Confidence
  }

  /// Why there is no check: too few days with logged food in the window.
  public struct Insufficient: Sendable, Equatable {
    public let asOf: Date
    public let daysLogged: Int
    public let daysRequired: Int
    public let reason: String
  }

  public enum Outcome: Sendable, Equatable {
    case evaluated(Check)
    case insufficientData(Insufficient)
  }

  /// The check on the window of `config.windowDays` days ending on the day of `date`.
  /// A day with no valid meal is absent, not 0 g, so any such day gives insufficient data.
  public static func check(asOf date: Date, meals: [Meal], config: Config) -> Outcome {
    precondition(config.windowDays > 0, "windowDays must be positive")
    let calendar = config.calendar
    let readDay = calendar.startOfDay(for: date)
    let days = (0..<config.windowDays).reversed().map {
      calendar.date(byAdding: .day, value: -$0, to: readDay)!
    }
    var byDay: [Date: [(low: Double, high: Double)]] = [:]
    for meal in meals {
      guard let range = validRange(meal) else { continue }
      let day = calendar.startOfDay(for: meal.date)
      if days.contains(day) { byDay[day, default: []].append(range) }
    }

    let logged = days.filter { byDay[$0] != nil }.count
    guard logged == config.windowDays else {
      let reason =
        "\(logged) of \(config.windowDays) days have logged food; "
        + "need all \(config.windowDays)"
      return .insufficientData(
        Insufficient(
          asOf: readDay, daysLogged: logged, daysRequired: config.windowDays, reason: reason))
    }

    let perDay = days.map { byDay[$0]! }
    let lows = perDay.map { $0.reduce(0) { $0 + $1.low } }
    let highs = perDay.map { $0.reduce(0) { $0 + $1.high } }
    let meanLow = lows.reduce(0, +) / Double(lows.count)
    let meanHigh = highs.reduce(0, +) / Double(highs.count)
    let fewest = perDay.map(\.count).min()!
    let level: Confidence.Level = fewest >= config.highMinMealsPerDay ? .high : .low
    let noun = fewest == 1 ? "meal" : "meals"
    let reason =
      "\(config.windowDays) of \(config.windowDays) days logged; "
      + "fewest on one day: \(fewest) \(noun); low end of each estimate used"
    return .evaluated(
      Check(
        asOf: readDay, windowStart: days[0], dailyLowGrams: lows, meanLowGrams: meanLow,
        meanHighGrams: meanHigh, floorGrams: config.floorGrams,
        isUnderFloor: meanLow < config.floorGrams,
        confidence: Confidence(level: level, reason: reason)))
  }

  /// The estimate as (low, high), ordered. Nil when either end is negative or not finite.
  private static func validRange(_ meal: Meal) -> (low: Double, high: Double)? {
    let a = meal.proteinLowGrams
    let b = meal.proteinHighGrams
    guard a.isFinite, b.isFinite, a >= 0, b >= 0 else { return nil }
    return (min(a, b), max(a, b))
  }
}
