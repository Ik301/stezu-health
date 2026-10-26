import Foundation
import StezuCore
import XCTest

final class HealthSourcesTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  func testTypeWithoutSamplesIsAbsent() async {
    let row = HealthSources.summarize(
      type: .heartRateVariability, latest: nil, recent: [], now: now)
    XCTAssertFalse(row.isPresent)
    XCTAssertNil(row.lastSampleDate)
    XCTAssertNil(row.recentSampleCount, "absent must not be a count of 0")
    XCTAssertTrue(row.recentSources.isEmpty)
    XCTAssertEqual(row.confidence.level, .low)
    XCTAssertEqual(row.confidence.reason, HealthSources.deniedHint)

    let rows = await HealthSources.load(from: FakeHealthStore(), now: now)
    XCTAssertEqual(rows.map(\.type), HealthType.allCases)
    XCTAssertTrue(rows.allSatisfy { !$0.isPresent && $0.recentSampleCount == nil })
  }

  func testCountsSamplesPerSourceOverLastSevenDays() async {
    let day = 86_400.0
    let samples = [
      HealthSample(type: .bodyMass, date: now - 1 * day, sourceName: "Strap", sourceBundleID: "a"),
      HealthSample(type: .bodyMass, date: now - 2 * day, sourceName: "Strap", sourceBundleID: "a"),
      HealthSample(type: .bodyMass, date: now - 3 * day, sourceName: "Stezu", sourceBundleID: "b"),
      HealthSample(type: .bodyMass, date: now - 9 * day, sourceName: "Old", sourceBundleID: "c"),
      HealthSample(type: .stepCount, date: now - 1 * day, sourceName: "Phone"),
    ]
    let rows = await HealthSources.load(from: FakeHealthStore(samples: samples), now: now)
    let weight = rows[0]
    XCTAssertEqual(weight.type, .bodyMass)
    XCTAssertEqual(weight.lastSampleDate, now - 1 * day)
    XCTAssertEqual(weight.recentSampleCount, 3)
    XCTAssertEqual(weight.recentSources.map(\.name), ["Strap", "Stezu"])
    XCTAssertEqual(weight.recentSources.map(\.count), [2, 1])

    let old = HealthSources.summarize(
      type: .bodyMass, latest: now - 9 * day, recent: [], now: now)
    XCTAssertTrue(old.isPresent)
    XCTAssertEqual(old.recentSampleCount, 0, "present but quiet this week is a real 0")
  }
}
