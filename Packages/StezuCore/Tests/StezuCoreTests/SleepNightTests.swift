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

/// S-037: the Home Data card's sleep summary.
extension SleepNightTests {
  /// A night ending on January `day`, 2026 with `minutes` asleep, starting at 23:00.
  private func night(_ day: Int, asleep minutes: Double) -> [SleepInterval] {
    [stage(.inBed, day, -70, minutes + 20), stage(.asleepCore, day, -60, minutes - 60)]
  }

  func testLastNightAsleepExcludesAwakeAndInBed() {
    // Sunday the 11th at noon; the night ending today has in-bed and awake stretches.
    let lastNight = [
      stage(.inBed, 11, -60, 420), stage(.asleepCore, 11, -45, 180),
      stage(.awake, 11, 180, 200), stage(.asleepREM, 11, 200, 400), stage(.awake, 11, 400, 420),
    ]
    let summary = SleepSummary.make(
      lastNight + night(10, asleep: 400), now: at(11, 720), calendar: calendar)
    XCTAssertEqual(summary.lastNight, (225 + 200) * 60)
    // The week runs Monday the 5th to Sunday the 11th, in hours; missing nights stay nil.
    XCTAssertEqual(summary.week, [nil, nil, nil, nil, nil, 400.0 / 60, 425.0 / 60])
  }

  func testUsualIsMedianOfRecordedNights() {
    // 35 recorded nights, every other day back from today: only the latest 30 count.
    let old = (0..<5).flatMap { night(-60 + 2 * $0, asleep: 600) }
    let recent = (0..<30).flatMap { night(11 - 2 * $0, asleep: 360 + Double($0)) }
    let summary = SleepSummary.make(old + recent, now: at(11, 720), calendar: calendar)
    XCTAssertEqual(summary.usual, (374 + 375) / 2 * 60)
    XCTAssertEqual(summary.confidence?.reason, "median of 30 nights")
    XCTAssertEqual(summary.confidence?.level, .high)

    // A night ending tomorrow (a nap after 18:00) is not part of the usual yet.
    let later = SleepSummary.make(
      night(10, asleep: 400) + [stage(.asleepCore, 11, 1140, 1200)], now: at(11, 1230),
      calendar: calendar)
    XCTAssertNil(later.lastNight)
    XCTAssertEqual(later.usual, 400 * 60)
  }

  func testNoNightIsAbsentNotZero() {
    let none = SleepSummary.make([], now: at(11, 720), calendar: calendar)
    XCTAssertNil(none.lastNight)
    XCTAssertNil(none.usual)
    XCTAssertNil(none.confidence)
    XCTAssertEqual(none.week, Array(repeating: nil, count: 7))
    XCTAssertEqual(none, SleepSummary.empty)

    // Only in bed and awake recorded: still no night, not a night of 0.
    let awake = SleepSummary.make(
      [stage(.inBed, 11, -60, 420), stage(.awake, 11, 0, 30)], now: at(11, 720),
      calendar: calendar)
    XCTAssertNil(awake.lastNight)
    XCTAssertNil(awake.usual)
  }
}
