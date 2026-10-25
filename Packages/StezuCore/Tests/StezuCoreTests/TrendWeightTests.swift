import Foundation
import StezuCore
import XCTest

// All weights are made-up example numbers, not anyone's data.
final class TrendWeightTests: XCTestCase {
  private var config: TrendWeightConfig {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return TrendWeightConfig(calendar: calendar)
  }

  private let start = Date(timeIntervalSince1970: 1_700_000_000)

  private func day(_ offset: Int, hour: Int = 0) -> Date {
    let base = config.calendar.startOfDay(for: start)
    return base.addingTimeInterval(Double(offset) * 86_400 + Double(hour) * 3_600)
  }

  func testFirstWeighInSeedsTrend() {
    let series = TrendWeight.series(
      [WeighIn(date: day(0, hour: 17), pounds: 150.0)], config: config)

    XCTAssertEqual(series.count, 1)
    XCTAssertEqual(series[0].trend, 150.0, accuracy: 1e-9)
    XCTAssertEqual(series[0].pounds, 150.0, accuracy: 1e-9)
    XCTAssertEqual(series[0].day, day(0))
    XCTAssertNil(series[0].gapDays)
    XCTAssertTrue(TrendWeight.series([], config: config).isEmpty)
  }

  func testGapUsesCompoundedAlpha() {
    let weighIns = [
      WeighIn(date: day(0), pounds: 150.0),
      WeighIn(date: day(1), pounds: 152.0),
      WeighIn(date: day(4), pounds: 154.0),
    ]
    let series = TrendWeight.series(weighIns, config: config)

    XCTAssertEqual(series.map(\.gapDays), [nil, 1, 3])
    // Gap of 1 day: weight 1 - 0.9^1 = 0.1.
    let afterOne = 150.0 + 0.1 * (152.0 - 150.0)
    XCTAssertEqual(series[1].trend, afterOne, accuracy: 1e-9)
    // Gap of 3 days: weight 1 - 0.9^3 = 0.271.
    let afterThree = afterOne + (1 - pow(0.9, 3)) * (154.0 - afterOne)
    XCTAssertEqual(series[2].trend, afterThree, accuracy: 1e-9)

    // Alpha is configurable.
    var custom = config
    custom.alpha = 0.5
    let fast = TrendWeight.series(weighIns, config: custom)
    XCTAssertEqual(fast[1].trend, 151.0, accuracy: 1e-9)
    XCTAssertEqual(fast[2].trend, 151.0 + 0.875 * 3.0, accuracy: 1e-9)

    // Unsorted input gives the same result.
    let shuffled = TrendWeight.series(weighIns.reversed(), config: config)
    XCTAssertEqual(shuffled.map(\.trend), series.map(\.trend))
  }

  func testMissingDaysAreNotZero() {
    let weighIns = [
      WeighIn(date: day(0), pounds: 150.0),
      WeighIn(date: day(5), pounds: 151.0),
    ]
    let series = TrendWeight.series(weighIns, config: config)

    // No points are made up for days 1 to 4.
    XCTAssertEqual(series.map(\.day), [day(0), day(5)])
    XCTAssertEqual(series[1].trend, 150.0 + (1 - pow(0.9, 5)) * 1.0, accuracy: 1e-9)

    // On a missing day the trend holds at the last value; it is not pulled toward 0.
    let midGap = TrendWeight.estimate(asOf: day(3), weighIns: weighIns, config: config)
    XCTAssertEqual(midGap?.trend ?? .nan, 150.0, accuracy: 1e-9)
    XCTAssertEqual(midGap?.lastWeighInDay, day(0))
    XCTAssertEqual(midGap?.daysSinceLastWeighIn, 3)

    // Before any weigh-in the trend is absent, not 0.
    XCTAssertNil(TrendWeight.estimate(asOf: day(-1), weighIns: weighIns, config: config))
    XCTAssertNil(TrendWeight.estimate(asOf: day(0), weighIns: [], config: config))

    // A weigh-in of 0 or a non-number is not a reading.
    let withBad =
      weighIns + [
        WeighIn(date: day(2), pounds: 0), WeighIn(date: day(3), pounds: .nan),
      ]
    XCTAssertEqual(TrendWeight.series(withBad, config: config).map(\.trend), series.map(\.trend))

    // Two weigh-ins on the same day count as one day, at their mean.
    let sameDay = [
      WeighIn(date: day(0, hour: 7), pounds: 150.0),
      WeighIn(date: day(0, hour: 19), pounds: 152.0),
    ]
    let merged = TrendWeight.series(sameDay, config: config)
    XCTAssertEqual(merged.count, 1)
    XCTAssertEqual(merged[0].trend, 151.0, accuracy: 1e-9)
  }

  func testTrendCarriesConfidence() {
    // One weigh-in: low.
    let single = TrendWeight.series([WeighIn(date: day(0), pounds: 150.0)], config: config)
    XCTAssertEqual(single[0].confidence.level, .low)
    XCTAssertFalse(single[0].confidence.reason.isEmpty)

    // Two weeks on a 5-day gym split (10 weigh-ins): high.
    let gymDays = [0, 1, 2, 3, 4, 7, 8, 9, 10, 11]
    let weighIns = gymDays.map { WeighIn(date: day($0), pounds: 150.0 + Double($0) * 0.05) }
    let series = TrendWeight.series(weighIns, config: config)
    XCTAssertEqual(series.last?.confidence.level, .high)
    XCTAssertTrue(series.last?.confidence.reason.contains("10 weigh-ins") ?? false)

    // One week (5 weigh-ins): medium.
    XCTAssertEqual(series[4].confidence.level, .medium)

    // Same data, read 5 days after the last weigh-in: medium, because it is stale.
    let stale = TrendWeight.estimate(asOf: day(16), weighIns: weighIns, config: config)
    XCTAssertEqual(stale?.confidence.level, .medium)
    // Read 10 days after: low.
    let old = TrendWeight.estimate(asOf: day(21), weighIns: weighIns, config: config)
    XCTAssertEqual(old?.confidence.level, .low)
    XCTAssertTrue(old?.confidence.reason.contains("10 days ago") ?? false)
  }
}
