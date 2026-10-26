import Foundation
import StezuCore
import XCTest

final class WeeklyStatTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  /// A day of January 2026 at `hour`. Monday the 5th starts the test week.
  private func day(_ day: Int, hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
  }

  func testCoverageCountsDaysWithData() async throws {
    let week = WeeklyStats.week(containing: day(11), calendar: calendar)
    XCTAssertEqual(week.start, day(5, hour: 0), "the week starts Monday")
    XCTAssertEqual(week.end, day(12, hour: 0))

    // Steps: daily totals Health merged; the Sunday before and the next Monday are outside.
    var totals: [Date: Double] = [day(4, hour: 0): 20_000, day(12, hour: 0): 20_000]
    for (offset, steps) in [6000.0, 8000, 7000, 9000, 5000, 7000].enumerated() {
      totals[day(5 + offset, hour: 0)] = steps
    }
    let steps = WeeklyStats.meanPerDay(totals, in: week)
    XCTAssertEqual(steps.value, 7000)
    XCTAssertEqual(steps.coverage, 6)
    XCTAssertEqual(steps.confidence.level, .high)
    XCTAssertEqual(steps.confidence.reason, "6 of 7 days with data")

    // Resting HR: each day's readings are averaged first, so two readings on one day count once.
    let resting = [(5, 58.0), (5, 62), (6, 57), (8, 60), (3, 90)].map {
      HealthSample(
        type: .restingHeartRate, date: day($0.0), sourceName: "Watch", value: $0.1)
    }
    let store = FakeHealthStore(samples: resting)
    let local = WeeklyStats.week(containing: day(11))
    let daily = try await store.dailyValues(of: .restingHeartRate, in: local)
    XCTAssertEqual(daily.values.sorted(), [57, 60, 60], "day 5's two readings average to 60")
    let heart = WeeklyStats.meanPerDay(daily, in: local)
    XCTAssertEqual(heart.value, 59)
    XCTAssertEqual(heart.coverage, 3)
    XCTAssertEqual(heart.confidence.level, .medium)

    // HRV: the median of every reading this week; coverage is the reading count.
    let hrv = [(5, 38.0), (6, 61), (7, 47), (7, 55), (9, 42), (2, 99)].map {
      HealthSample(
        type: .heartRateVariability, date: day($0.0), sourceName: "Watch", value: $0.1)
    }
    let median = WeeklyStats.median(hrv, in: week)
    XCTAssertEqual(median.value, 47)
    XCTAssertEqual(median.coverage, 5)
    XCTAssertEqual(median.confidence.reason, "5 samples this week")
  }

  func testNoDataIsAbsentNotZero() async {
    let week = WeeklyStats.week(containing: day(11), calendar: calendar)
    let stats = [
      WeeklyStats.meanPerDay([:], in: week),
      WeeklyStats.meanPerDay([:], in: week, of: "of 7 nights with data"),
      WeeklyStats.median([], in: week),
      WeeklyStats.sleep([], in: week, calendar: calendar),
    ]
    for stat in stats {
      XCTAssertNil(stat.value, "no data must be absent, not 0")
      XCTAssertEqual(stat.coverage, 0)
      XCTAssertEqual(stat.confidence.level, .low)
      XCTAssertEqual(stat.confidence.reason, HealthSources.deniedHint)
    }

    // A denied or empty store reads the same: every metric absent.
    let health = await WeeklyHealth.load(from: FakeHealthStore(), now: day(11))
    for stat in [health.steps, health.sleep, health.hrv, health.restingHeartRate] {
      XCTAssertNil(stat.value)
      XCTAssertEqual(stat.coverage, 0)
    }
  }
}
