import Foundation
import StezuCore
import XCTest

final class HealthStoreTests: XCTestCase {
  func testFakeStoreReturnsBodyMassSamples() async throws {
    let samples = [
      WeightFixture.stezu(5, 170.0), WeightFixture.strap(6, 150.0), WeightFixture.stezu(7, 169.6),
      HealthSample(type: .stepCount, date: WeightFixture.day(7), sourceName: "Phone"),
    ]
    let store = FakeHealthStore(samples: samples)
    let read = try await store.samples(of: .bodyMass, since: WeightFixture.day(6, hour: 0))
    XCTAssertEqual(read.map(\.value), [150.0, 169.6])
    XCTAssertEqual(read.map(\.sourceName), ["Strap", "Stezu"])

    // The strap's profile weight is not a weigh-in.
    let week = WeeklyWeight.week(
      of: samples, now: WeightFixture.now, calendar: WeightFixture.calendar)
    XCTAssertEqual(week.daysWeighed, 2)
    XCTAssertEqual(week.sources, ["Stezu"])
    XCTAssertEqual(week.weekStart, WeightFixture.day(5, hour: 0))
  }

  func testDeniedAccessIsAbsentNotZero() async {
    // HealthKit hides denied reads, so a denied store looks like an empty one.
    let loaded = await WeeklyWeight.load(
      from: FakeHealthStore(), now: WeightFixture.now, calendar: WeightFixture.calendar)
    XCTAssertNil(loaded.week.trend)
    XCTAssertNil(loaded.week.change)
    XCTAssertNil(loaded.week.daysWeighed)
    XCTAssertNil(loaded.prefill)
    XCTAssertEqual(loaded.week.confidence.reason, WeeklyWeight.noWeighInsReason)

    // Weigh-ins only before this week: this week is still absent.
    let old = WeeklyWeight.week(
      of: [WeightFixture.stezu(2, 170.0)], now: WeightFixture.now,
      calendar: WeightFixture.calendar)
    XCTAssertNil(old.trend)
    XCTAssertNil(old.daysWeighed)
  }
}
