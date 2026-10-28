import Foundation

/// A nutrient amount as a low-high range. Food amounts from a photo are never one number.
public struct FoodRange: Sendable, Equatable, Codable {
  public let low: Double
  public let high: Double

  public init(low: Double, high: Double) {
    self.low = min(low, high)
    self.high = max(low, high)
  }

  /// The meal total: lows summed and highs summed. Nil when the list is empty or any item has no
  /// range, because an unknown item makes the whole total unknown (absent is not zero).
  public static func total(_ ranges: [FoodRange?]) -> FoodRange? {
    guard !ranges.isEmpty else { return nil }
    var low = 0.0
    var high = 0.0
    for range in ranges {
      guard let range else { return nil }
      low += range.low
      high += range.high
    }
    return FoodRange(low: low, high: high)
  }

  /// How every food range is written (RangeValue, S-050): whole numbers with thousands commas
  /// and an en dash, such as "1,240–1,480 kcal", or "-- kcal" when unknown. Never a midpoint.
  public static func text(_ range: FoodRange?, unit: String? = nil) -> String {
    let numbers = range.map { "\(grouped($0.low))\u{2013}\(grouped($0.high))" } ?? "--"
    return unit.map { "\(numbers) \($0)" } ?? numbers
  }

  private static func grouped(_ value: Double) -> String {
    var digits = String(Int(value.rounded()))
    var end = digits.endIndex
    while digits.distance(from: digits.startIndex, to: end) > 3 {
      end = digits.index(end, offsetBy: -3)
      digits.insert(",", at: end)
    }
    return digits
  }
}
