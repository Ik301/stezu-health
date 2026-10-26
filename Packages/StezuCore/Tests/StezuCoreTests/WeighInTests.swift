import Foundation
import StezuCore
import XCTest

final class WeighInTests: XCTestCase {
  func testOneTapWritesOneSample() async throws {
    let store = FakeHealthStore(samples: [
      WeightFixture.stezu(2, 171.0), WeightFixture.stezu(5, 170.0),
    ])
    let before = await WeeklyWeight.load(
      from: store, now: WeightFixture.now, calendar: WeightFixture.calendar)
    XCTAssertEqual(before.week.daysWeighed, 1)

    try await WeeklyWeight.weighIn(pounds: 169.44, at: WeightFixture.day(10), to: store)
    let stored = await store.storedSamples
    XCTAssertEqual(stored.count, 3)
    XCTAssertEqual(stored.last?.type, .bodyMass)
    XCTAssertEqual(stored.last?.value, 169.4)
    XCTAssertEqual(stored.last?.sourceBundleID, WeeklyWeight.stezuBundleID)

    let after = await WeeklyWeight.load(
      from: store, now: WeightFixture.now, calendar: WeightFixture.calendar)
    XCTAssertEqual(after.week.daysWeighed, 2)
    XCTAssertEqual(after.prefill, 169.4)
    let change = try XCTUnwrap(after.week.change)
    XCTAssertLessThan(change, 0)
    XCTAssertNotNil(after.week.trend)
  }

  func testPrefillUsesLastWeighIn() {
    // The last Stezu weigh-in wins over a newer strap sample.
    let samples = [
      WeightFixture.stezu(5, 170.0), WeightFixture.stezu(8, 169.66), WeightFixture.strap(9, 150.0),
    ]
    XCTAssertEqual(WeeklyWeight.prefill(from: samples), 169.7)
    // With no Stezu weigh-in, the last sample from any app.
    XCTAssertEqual(WeeklyWeight.prefill(from: [WeightFixture.strap(9, 150.0)]), 150.0)
    XCTAssertNil(WeeklyWeight.prefill(from: []))
  }
}
