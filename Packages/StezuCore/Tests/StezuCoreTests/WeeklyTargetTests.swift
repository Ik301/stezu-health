import Foundation
import StezuCore
import XCTest

// All weights and kcal targets are made-up example numbers, not anyone's data.
final class WeeklyTargetTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  /// alpha 1 makes the trend equal the latest reading, so the trend rate is exact.
  private func config(raiseStep: Double = 100) -> WeeklyTargetConfig {
    WeeklyTargetConfig(raiseStep: raiseStep, trend: TrendWeightConfig(alpha: 1, calendar: calendar))
  }

  private let start = Date(timeIntervalSince1970: 1_700_000_000)

  private func day(_ offset: Int) -> Date {
    calendar.startOfDay(for: start).addingTimeInterval(Double(offset) * 86_400 + 8 * 3_600)
  }

  /// Daily weigh-ins on the given days, gaining `perWeek` pounds a week from 140.
  private func weighIns(_ days: [Int], perWeek: Double) -> [WeighIn] {
    days.map { WeighIn(date: day($0), pounds: 140 + perWeek * Double($0) / 7) }
  }

  func testFewerThanFourWeighInsMakesNoChange() {
    // Four weeks of daily data, but only 3 weigh-ins in the last 7 days.
    let readings = weighIns(Array(0...21) + [24, 26, 28], perWeek: 0)
    let decision = WeeklyTarget.evaluate(
      asOf: day(28), currentTarget: 2500, weighIns: readings, lastChange: nil, config: config())
    XCTAssertEqual(decision.action, .insufficientData)
    XCTAssertEqual(decision.newTarget, 2500)
    XCTAssertNil(decision.trendRate)
    XCTAssertEqual(decision.confidence.level, .low)
    XCTAssertTrue(decision.reason.contains("3 weigh-ins"), decision.reason)
  }

  func testFewerThan21DaysMakesNoChange() {
    // Daily weigh-ins, but the first one is only 20 days before the read day.
    let readings = weighIns(Array(8...28), perWeek: 0)
    let decision = WeeklyTarget.evaluate(
      asOf: day(28), currentTarget: 2500, weighIns: readings, lastChange: nil, config: config())
    XCTAssertEqual(decision.action, .insufficientData)
    XCTAssertEqual(decision.newTarget, 2500)
    XCTAssertNil(decision.trendRate)
    XCTAssertTrue(decision.reason.contains("20 days"), decision.reason)

    // No weigh-ins at all is absent data, not a rate of 0.
    let empty = WeeklyTarget.evaluate(
      asOf: day(28), currentTarget: 2500, weighIns: [], lastChange: nil, config: config())
    XCTAssertEqual(empty.action, .insufficientData)
    XCTAssertNil(empty.trendRate)
  }

  func testRaisesTargetWhenTrendIsUnderRate() {
    // Flat weight: 0 lb/week against a 0.35 target is 0.35 under, more than 0.15.
    let flat = WeeklyTarget.evaluate(
      asOf: day(28), currentTarget: 2500, weighIns: weighIns(Array(0...28), perWeek: 0),
      lastChange: nil, config: config(raiseStep: 150))
    XCTAssertEqual(flat.action, .raise)
    XCTAssertEqual(flat.newTarget, 2650)
    XCTAssertEqual(flat.trendRate ?? .nan, 0, accuracy: 1e-9)
    XCTAssertEqual(flat.confidence.level, .high)
    XCTAssertFalse(flat.reason.isEmpty)

    // 0.25 lb/week is only 0.10 under: no change.
    let near = WeeklyTarget.evaluate(
      asOf: day(28), currentTarget: 2500, weighIns: weighIns(Array(0...28), perWeek: 0.25),
      lastChange: nil, config: config())
    XCTAssertEqual(near.action, .hold)
    XCTAssertEqual(near.newTarget, 2500)
    XCTAssertEqual(near.trendRate ?? .nan, 0.25, accuracy: 1e-9)
  }

  func testLowersTargetWhenTrendIsOverRate() {
    // 1 lb/week against 0.35 is 0.65 over, more than 0.25.
    let fast = WeeklyTarget.evaluate(
      asOf: day(28), currentTarget: 2500, weighIns: weighIns(Array(0...28), perWeek: 1),
      lastChange: nil, config: config())
    XCTAssertEqual(fast.action, .lower)
    XCTAssertEqual(fast.newTarget, 2400)
    XCTAssertEqual(fast.trendRate ?? .nan, 1, accuracy: 1e-9)

    // 0.55 lb/week is only 0.20 over: no change.
    let near = WeeklyTarget.evaluate(
      asOf: day(28), currentTarget: 2500, weighIns: weighIns(Array(0...28), perWeek: 0.55),
      lastChange: nil, config: config())
    XCTAssertEqual(near.action, .hold)
    XCTAssertEqual(near.newTarget, 2500)
  }

  func testAtMostOneChangePerWeek() {
    let flat = weighIns(Array(0...28), perWeek: 0)
    // Changed 6 days ago: a raise is due but is held.
    let recent = WeeklyTarget.evaluate(
      asOf: day(28), currentTarget: 2600, weighIns: flat, lastChange: day(22), config: config())
    XCTAssertEqual(recent.action, .alreadyChangedThisWeek)
    XCTAssertEqual(recent.newTarget, 2600)
    XCTAssertNotNil(recent.trendRate)
    XCTAssertTrue(recent.reason.contains("already changed"), recent.reason)

    // Changed 7 days ago: the next change is allowed.
    let weekLater = WeeklyTarget.evaluate(
      asOf: day(28), currentTarget: 2600, weighIns: flat, lastChange: day(21), config: config())
    XCTAssertEqual(weekLater.action, .raise)
    XCTAssertEqual(weekLater.newTarget, 2700)
  }
}
