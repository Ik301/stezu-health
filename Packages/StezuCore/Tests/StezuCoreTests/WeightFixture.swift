import Foundation
import StezuCore
import XCTest

/// Synthetic weigh-ins only (D-034). The week is Mon 2026-01-05 to Sun 2026-01-11, UTC.
enum WeightFixture {
  static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }
  static func day(_ day: Int, hour: Int = 8) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
  }
  static func stezu(_ day: Int, _ pounds: Double) -> HealthSample {
    HealthSample(
      type: .bodyMass, date: Self.day(day), sourceName: "Stezu",
      sourceBundleID: WeeklyWeight.stezuBundleID, value: pounds)
  }
  static func strap(_ day: Int, _ pounds: Double) -> HealthSample {
    HealthSample(
      type: .bodyMass, date: Self.day(day), sourceName: "Strap", sourceBundleID: "example.strap",
      value: pounds)
  }
  static let now = day(10, hour: 18)
}
