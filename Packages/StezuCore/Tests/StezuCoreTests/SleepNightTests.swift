import Foundation
import StezuCore
import XCTest

final class SleepNightTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  /// Minutes from midnight of January `day`, 2026 (negative is the evening before).
  private func at(_ day: Int, _ minutes: Double) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 1, day: day))! + minutes * 60
  }

  private func stage(_ stage: SleepStage, _ day: Int, _ from: Double, _ to: Double)
    -> SleepInterval
  {
    (start: at(day, from), end: at(day, to), stage: stage)
  }

  func testNightSumsAsleepStages() {
    let tuesday = [
      stage(.inBed, 6, -60, 420),
      stage(.asleepCore, 6, -45, 180),
      stage(.asleepDeep, 6, 180, 240),
      stage(.asleepREM, 6, 240, 330),
      stage(.awake, 6, 330, 340),
      stage(.asleepCore, 6, 340, 405),
      // A second app recorded the same stretch: it counts once.
      stage(.asleepUnspecified, 6, 0, 120),
    ]
    // A nap ending in the afternoon belongs to the night that ended that morning.
    let wednesday = [stage(.asleepUnspecified, 7, -90, 360), stage(.asleepCore, 7, 900, 960)]
    let nights = SleepNights.nights(tuesday + wednesday, calendar: calendar)
    XCTAssertEqual(nights.keys.sorted(), [at(6, 0), at(7, 0)])
    XCTAssertEqual(nights[at(6, 0)], (225 + 60 + 90 + 65) * 60, "in bed and awake do not count")
    XCTAssertEqual(nights[at(7, 0)], (450 + 60) * 60)

    let week = WeeklyStats.week(containing: at(11, 720), calendar: calendar)
    let sleep = WeeklyStats.sleep(tuesday + wednesday, in: week, calendar: calendar)
    XCTAssertEqual(sleep.value, (440 + 510) * 60 / 2)
    XCTAssertEqual(sleep.coverage, 2)
    XCTAssertEqual(sleep.confidence.reason, "2 of 7 nights with data")
  }
}
