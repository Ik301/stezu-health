import Foundation
import StezuCore
import XCTest

// All protein numbers and the floor are made-up example values, not anyone's data.
final class ProteinFloorTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private var config: ProteinFloor.Config {
    ProteinFloor.Config(floorGrams: 100, calendar: calendar)
  }

  private let start = Date(timeIntervalSince1970: 1_700_000_000)

  private func day(_ offset: Int, hour: Int = 12) -> Date {
    calendar.startOfDay(for: start)
      .addingTimeInterval(Double(offset) * 86_400 + Double(hour) * 3_600)
  }

  private func meal(_ offset: Int, _ low: Double, _ high: Double, hour: Int = 12)
    -> ProteinFloor.Meal
  {
    ProteinFloor.Meal(date: day(offset, hour: hour), proteinLowGrams: low, proteinHighGrams: high)
  }

  func testFlagsWhenThreeDayMeanIsUnderFloor() {
    // Daily lows 90, 80, 100: mean 90, under the floor of 100.
    let under = [
      meal(0, 50, 60, hour: 8), meal(0, 40, 50, hour: 19),
      meal(1, 80, 95),
      meal(2, 60, 70, hour: 8), meal(2, 40, 45, hour: 19),
    ]
    guard
      case .evaluated(let check) = ProteinFloor.check(asOf: day(2), meals: under, config: config)
    else { return XCTFail("expected an evaluated check") }
    XCTAssertEqual(check.meanLowGrams, 90, accuracy: 1e-9)
    XCTAssertEqual(check.floorGrams, 100, accuracy: 1e-9)
    XCTAssertTrue(check.isUnderFloor)
    XCTAssertEqual(check.dailyLowGrams, [90, 80, 100])
    XCTAssertEqual(check.windowStart, day(0, hour: 0))
    XCTAssertFalse(check.confidence.reason.isEmpty)

    // Daily lows 110, 100, 120: mean 110, not flagged.
    let over = [meal(0, 110, 130), meal(1, 100, 120), meal(2, 120, 140)]
    guard case .evaluated(let ok) = ProteinFloor.check(asOf: day(2), meals: over, config: config)
    else { return XCTFail("expected an evaluated check") }
    XCTAssertEqual(ok.meanLowGrams, 110, accuracy: 1e-9)
    XCTAssertFalse(ok.isUnderFloor)

    // A mean exactly on the floor is not under it.
    let equal = [meal(0, 100, 120), meal(1, 100, 120), meal(2, 100, 120)]
    guard case .evaluated(let edge) = ProteinFloor.check(asOf: day(2), meals: equal, config: config)
    else { return XCTFail("expected an evaluated check") }
    XCTAssertFalse(edge.isUnderFloor)

    // The window rolls: meals from before it and after the read day do not count.
    let rolling = over + [meal(-1, 10, 20), meal(3, 10, 20)]
    guard
      case .evaluated(let rolled) = ProteinFloor.check(
        asOf: day(2), meals: rolling, config: config)
    else { return XCTFail("expected an evaluated check") }
    XCTAssertEqual(rolled.meanLowGrams, 110, accuracy: 1e-9)
  }

  func testUsesLowEndOfEstimateRange() {
    // Highs average 115, above the floor; lows average 95, under it. The low end decides.
    let meals = [meal(0, 95, 115), meal(1, 90, 110), meal(2, 100, 120)]
    guard
      case .evaluated(let check) = ProteinFloor.check(asOf: day(2), meals: meals, config: config)
    else { return XCTFail("expected an evaluated check") }
    XCTAssertEqual(check.meanLowGrams, 95, accuracy: 1e-9)
    XCTAssertEqual(check.meanHighGrams, 115, accuracy: 1e-9)
    XCTAssertTrue(check.isUnderFloor)

    // A range given high-first is read by its lower bound, not its first number.
    let swapped = [
      ProteinFloor.Meal(date: day(0), proteinLowGrams: 115, proteinHighGrams: 95),
      meal(1, 90, 110), meal(2, 100, 120),
    ]
    guard
      case .evaluated(let fixed) = ProteinFloor.check(
        asOf: day(2), meals: swapped, config: config)
    else { return XCTFail("expected an evaluated check") }
    XCTAssertEqual(fixed.meanLowGrams, 95, accuracy: 1e-9)
  }

  func testFewerThanThreeDaysIsInsufficient() {
    // No meals at all.
    guard
      case .insufficientData(let none) = ProteinFloor.check(
        asOf: day(2), meals: [], config: config)
    else { return XCTFail("no food logged must be insufficient data") }
    XCTAssertEqual(none.daysLogged, 0)
    XCTAssertEqual(none.daysRequired, 3)
    XCTAssertFalse(none.reason.isEmpty)

    // Two logged days with a very low intake: still no flag, because day 1 is missing,
    // and a missing day is absent, not 0 grams.
    let twoDays = [meal(0, 5, 10), meal(2, 5, 10)]
    guard
      case .insufficientData(let two) = ProteinFloor.check(
        asOf: day(2), meals: twoDays, config: config)
    else { return XCTFail("two logged days must be insufficient data") }
    XCTAssertEqual(two.daysLogged, 2)

    // Invalid estimates (negative or not finite) do not make a day logged.
    let invalid = [meal(0, 120, 140), meal(1, -5, 10), meal(1, .nan, 10), meal(2, 120, 140)]
    guard
      case .insufficientData(let bad) = ProteinFloor.check(
        asOf: day(2), meals: invalid, config: config)
    else { return XCTFail("invalid estimates must not count as a logged day") }
    XCTAssertEqual(bad.daysLogged, 2)

    // A meal estimated at 0 grams is a real, logged value.
    let zero = [meal(0, 0, 0), meal(1, 120, 140), meal(2, 120, 140)]
    guard
      case .evaluated(let logged) = ProteinFloor.check(asOf: day(2), meals: zero, config: config)
    else { return XCTFail("a 0 g meal is logged food") }
    XCTAssertEqual(logged.meanLowGrams, 80, accuracy: 1e-9)
  }
}
