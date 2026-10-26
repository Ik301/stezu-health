import Foundation
import StezuCore
import XCTest

final class MetricHistoryTests: XCTestCase {
  private let calendar = Calendar.current

  /// A day of January 2026 (0 and below roll back into December) at `hour`, in the device's
  /// calendar, which FakeHealthStore keys its days by. Monday the 5th starts the current week.
  private func day(_ day: Int, hour: Int = 9) -> Date {
    let first = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour))!
    return calendar.date(byAdding: .day, value: day - 1, to: first)!
  }

  private func sample(
    _ type: HealthType, _ day: Int, _ value: Double, from source: String = "Phone"
  )
    -> HealthSample
  {
    HealthSample(
      type: type, date: self.day(day, hour: 7), sourceName: source,
      sourceBundleID: source == "Stezu" ? WeeklyWeight.stezuBundleID : "example.\(source)",
      value: value)
  }

  func testEightWeeksWithCoverage() async {
    let now = day(11, hour: 12)
    let store = FakeHealthStore(samples: [
      // Steps: two days this week, one the week before, one in the oldest week, one too old.
      sample(.stepCount, 5, 5000), sample(.stepCount, 6, 7000), sample(.stepCount, -1, 3000),
      sample(.stepCount, -44, 4000), sample(.stepCount, -51, 9000),
      // Weight: Stezu on Monday and Wednesday; a strap's Tuesday weight does not count.
      sample(.bodyMass, 5, 170, from: "Stezu"), sample(.bodyMass, 7, 169, from: "Stezu"),
      sample(.bodyMass, 6, 150, from: "Strap"),
    ])

    let steps = await MetricHistory.load(.steps, from: store, now: now, calendar: calendar)
    XCTAssertEqual(steps.weeks.count, 8)
    XCTAssertEqual(steps.weeks[0].start, day(5, hour: 0), "the newest week starts this Monday")
    XCTAssertEqual(steps.weeks[7].start, day(-44, hour: 0), "8 weeks back, Monday 2025-11-17")
    XCTAssertEqual(steps.weeks[0].days.map(\.day), (5...11).map { day($0, hour: 0) })
    XCTAssertEqual(steps.weeks[0].days.map(\.value), [5000, 7000, nil, nil, nil, nil, nil])
    XCTAssertEqual(steps.weeks[0].stat.value, 6000)
    XCTAssertEqual(steps.weeks[0].stat.coverage, 2)
    XCTAssertEqual(steps.weeks[1].stat.value, 3000)
    XCTAssertEqual(steps.weeks[1].stat.coverage, 1)
    XCTAssertNil(steps.weeks[3].stat.value, "an empty week is absent, not 0")
    XCTAssertEqual(steps.weeks[3].stat.coverage, 0)
    XCTAssertEqual(steps.weeks[3].stat.confidence.level, .low)
    XCTAssertEqual(steps.weeks[7].stat.coverage, 1, "the sample from 9 weeks back is left out")
    XCTAssertEqual(steps.sources, ["Phone"])

    let weight = await MetricHistory.load(.weight, from: store, now: now, calendar: calendar)
    XCTAssertEqual(weight.weeks[0].stat.coverage, 2)
    XCTAssertEqual(weight.weeks[0].days.map(\.value), [170, nil, 169, nil, nil, nil, nil])
    XCTAssertEqual(weight.trend.map(\.pounds), [170, 169])
    XCTAssertEqual(weight.weeks[0].stat.value, weight.trend.last?.trend)
    XCTAssertNil(weight.weeks[1].stat.value)
    XCTAssertEqual(weight.sources, ["Stezu"])

    let sleep = await MetricHistory.load(.sleep, from: store, now: now, calendar: calendar)
    XCTAssertEqual(sleep.weeks.count, 8)
    XCTAssertTrue(sleep.weeks.allSatisfy { $0.stat.value == nil && $0.stat.coverage == 0 })
    XCTAssertTrue(
      sleep.weeks.allSatisfy { $0.days.count == 7 && $0.days.allSatisfy { $0.value == nil } })
  }
}
