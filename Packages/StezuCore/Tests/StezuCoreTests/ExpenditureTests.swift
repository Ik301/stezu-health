import Foundation
import StezuCore
import XCTest

// All intakes and weights are made-up example numbers, not anyone's data.
final class ExpenditureTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  /// alpha 1 makes the trend equal the latest reading, so the trend change is exact.
  private var config: ExpenditureConfig {
    ExpenditureConfig(trend: TrendWeightConfig(alpha: 1, calendar: calendar))
  }

  private let start = Date(timeIntervalSince1970: 1_700_000_000)

  /// Day 0 is the day before the window; days 1...21 are the window when read on day 21.
  private func day(_ offset: Int, hour: Int = 12) -> Date {
    calendar.startOfDay(for: start).addingTimeInterval(
      Double(offset) * 86_400 + Double(hour) * 3_600)
  }

  private func intake(days: ClosedRange<Int>, kcal: Double) -> [IntakeEntry] {
    days.map { IntakeEntry(date: day($0), kcal: kcal) }
  }

  func testExpenditureFromIntakeAndTrendChange() throws {
    // Two meals a day, 1200 + 800 kcal, so daily totals are 2000.
    let meals =
      intake(days: 1...21, kcal: 1200)
      + (1...21).map { IntakeEntry(date: day($0, hour: 19), kcal: 800) }
    // Daily weigh-ins, so both window edges have a high-confidence trend.
    let weighIns =
      (-13...0).map { WeighIn(date: day($0), pounds: 151.5) }
      + (1...20).map { WeighIn(date: day($0), pounds: 151.0) }
      + [WeighIn(date: day(21), pounds: 150.0)]

    let result = Expenditure.estimate(
      asOf: day(21), intake: meals, weighIns: weighIns, config: config)
    let estimate = try XCTUnwrap(result.estimate)

    // 2000 - (-1.5 lb x 3500) / 21 = 2000 + 250.
    XCTAssertEqual(estimate.meanIntake, 2000, accuracy: 1e-9)
    XCTAssertEqual(estimate.trendChange, -1.5, accuracy: 1e-9)
    XCTAssertEqual(estimate.kcalPerDay, 2250, accuracy: 1e-9)
    XCTAssertEqual(estimate.includedDays, 21)
    XCTAssertEqual(estimate.partialDays, 0)
    XCTAssertEqual(estimate.confidence.level, .high)
    XCTAssertFalse(estimate.confidence.reason.isEmpty)

    // Intake before the window does not count.
    let withOld = meals + intake(days: -5...0, kcal: 5000)
    let same = Expenditure.estimate(
      asOf: day(21), intake: withOld, weighIns: weighIns, config: config)
    XCTAssertEqual(try XCTUnwrap(same.estimate).kcalPerDay, 2250, accuracy: 1e-9)
  }

  func testPartialDaysAreExcluded() throws {
    // Steady weight, so expenditure equals the mean of the full days.
    var entries = intake(days: 1...21, kcal: 2100)
    // Day 3 and day 16 are partial logs (under 50% of their week's median of 2100).
    entries.removeAll { [day(3), day(16)].contains($0.date) }
    entries += [IntakeEntry(date: day(3), kcal: 600), IntakeEntry(date: day(16), kcal: 900)]
    // Day 9 is a low but real day (at least 50% of the median), so it stays.
    entries.removeAll { $0.date == day(9) }
    entries.append(IntakeEntry(date: day(9), kcal: 1260))
    // Day 12 has no log at all: absent, not a 0-kcal day.
    entries.removeAll { $0.date == day(12) }
    let weighIns = [WeighIn(date: day(0), pounds: 150), WeighIn(date: day(21), pounds: 150)]

    let result = Expenditure.estimate(
      asOf: day(21), intake: entries, weighIns: weighIns, config: config)
    let estimate = try XCTUnwrap(result.estimate)

    XCTAssertEqual(estimate.partialDays, 2)
    XCTAssertEqual(estimate.includedDays, 18)
    let expectedMean = (2100.0 * 17 + 1260) / 18
    XCTAssertEqual(estimate.meanIntake, expectedMean, accuracy: 1e-9)
    XCTAssertEqual(estimate.kcalPerDay, expectedMean, accuracy: 1e-9)
    XCTAssertEqual(estimate.trendChange, 0, accuracy: 1e-9)
  }

  func testInsufficientDataIsNotZero() {
    let weighIns = [WeighIn(date: day(0), pounds: 150), WeighIn(date: day(21), pounds: 149)]
    let fullIntake = intake(days: 1...21, kcal: 2000)

    // No intake logged at all.
    let noIntake = Expenditure.estimate(
      asOf: day(21), intake: [], weighIns: weighIns, config: config)
    XCTAssertNil(noIntake.estimate)
    guard case .insufficientData(let reason) = noIntake else {
      return XCTFail("expected insufficient data")
    }
    XCTAssertFalse(reason.isEmpty)

    // Too few logged days in the window.
    let fewDays = Expenditure.estimate(
      asOf: day(21), intake: intake(days: 18...21, kcal: 2000), weighIns: weighIns, config: config)
    XCTAssertNil(fewDays.estimate)

    // No weigh-ins: there is no trend change.
    let noWeights = Expenditure.estimate(
      asOf: day(21), intake: fullIntake, weighIns: [], config: config)
    XCTAssertNil(noWeights.estimate)

    // The first weigh-in is inside the window: the trend at the window start is unknown.
    let lateStart = Expenditure.estimate(
      asOf: day(21), intake: fullIntake,
      weighIns: [WeighIn(date: day(5), pounds: 150), WeighIn(date: day(21), pounds: 149)],
      config: config)
    XCTAssertNil(lateStart.estimate)
    guard case .insufficientData = lateStart else { return XCTFail("expected insufficient data") }

    // Zero-kcal entries are not intake.
    let zeros = Expenditure.estimate(
      asOf: day(21), intake: intake(days: 1...21, kcal: 0), weighIns: weighIns, config: config)
    XCTAssertNil(zeros.estimate)
  }
}
