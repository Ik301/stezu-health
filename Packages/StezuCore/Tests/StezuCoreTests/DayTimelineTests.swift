import Foundation
import StezuCore
import XCTest

/// S-041: the Day view's timeline. Hours with a mark are full height, empty hours fold, marks
/// sit at their time, clipped to the day, and overlapping marks share the width in lanes.
final class DayTimelineTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  /// Minutes from midnight of Monday, January 5th 2026 (negative is the evening before).
  private func at(_ minutes: Double) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))! + minutes * 60
  }

  private func span(_ from: Double, _ to: Double) -> DateInterval {
    DateInterval(start: at(from), end: at(to))
  }

  private let (full, folded) = (DayTimeline.fullHour, DayTimeline.foldedHour)

  func testEmptyHoursFold() {
    // A night from 23:00 to 06:45, a weigh-in at 07:00 and a meal at 12:30.
    let timeline = DayTimeline(
      day: at(600), spans: [span(-60, 405), span(420, 420), span(750, 750)], calendar: calendar)
    let open = timeline.hours.indices.filter { timeline.hours[$0] == full }
    // The meal's point keeps the hour after it open too, so its mark has room.
    XCTAssertEqual(open, [0, 1, 2, 3, 4, 5, 6, 7, 12, 13])
    XCTAssertEqual(timeline.hours.filter { $0 == folded }.count, 14)
    XCTAssertEqual(timeline.height, 10 * full + 14 * folded)

    // Nothing recorded: every hour folds, and there are no marks.
    let empty = DayTimeline(day: at(0), spans: [], calendar: calendar)
    XCTAssertEqual(empty.hours, Array(repeating: folded, count: 24))
    XCTAssertTrue(empty.marks.isEmpty)
  }

  func testBlocksPositionedByTimeAndClippedToDay() {
    // The night began the day before, a workout runs 18:00 to 19:30, a late session runs past
    // midnight, and a meal the next day is outside.
    let timeline = DayTimeline(
      day: at(0), spans: [span(-60, 405), span(1080, 1170), span(1410, 1500), span(1500, 1510)],
      calendar: calendar)
    let (night, workout, late) = (timeline.marks[0]!, timeline.marks[1]!, timeline.marks[2]!)
    XCTAssertEqual(night.top, 0, "clipped to midnight")
    XCTAssertEqual(night.height, 6.75 * full, accuracy: 0.001)
    // 07:00 to 18:00: 7 open hours, then 11 folded hours before the workout.
    XCTAssertEqual(workout.top, 7 * full + 11 * folded, accuracy: 0.001)
    XCTAssertEqual(workout.height, 1.5 * full, accuracy: 0.001)
    XCTAssertEqual(timeline.y(at(1110)), workout.top + full / 2, accuracy: 0.001)
    XCTAssertEqual(late.top + late.height, timeline.height, accuracy: 0.001, "clipped at 24:00")
    XCTAssertNil(timeline.marks[3], "the next day is not on this one")
    XCTAssertEqual(timeline.y(at(-30)), 0)
    XCTAssertEqual(timeline.y(at(1500)), timeline.height)
  }

  func testOverlappingBlocksGetSeparateLanes() {
    // Two meals logged at 12:00, then a workout at 18:00 that overlaps neither.
    let timeline = DayTimeline(
      day: at(0), spans: [span(720, 720), span(720, 725), span(1080, 1140)], calendar: calendar)
    let (first, second, workout) = (timeline.marks[0]!, timeline.marks[1]!, timeline.marks[2]!)
    XCTAssertEqual([first.lane, second.lane], [0, 1])
    XCTAssertEqual([first.lanes, second.lanes], [2, 2])
    XCTAssertEqual(first.top, second.top)
    XCTAssertEqual(first.height, DayTimeline.shortest, "a point is a tap target tall")
    XCTAssertEqual(workout.lane, 0)
    XCTAssertEqual(workout.lanes, 1)

    // A mark that starts after the first lane frees up reuses it.
    let staggered = DayTimeline(
      day: at(0), spans: [span(600, 690), span(630, 720), span(700, 760)], calendar: calendar)
    XCTAssertEqual(staggered.marks.map { $0!.lane }, [0, 1, 0])
    XCTAssertEqual(staggered.marks.map { $0!.lanes }, [2, 2, 2])
  }
}
