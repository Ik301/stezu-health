import Foundation
import StezuCore
import XCTest

/// What the home-screen widgets draw from GET /surface/today (S-060, S-061). Words and goals are synthetic.
final class SurfaceTodayTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
  }

  private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
  }

  func testMissingFieldsShowDashes() throws {
    let json =
      #"{"date": "2026-03-11", "word": null, "definition": null, "goal": null, "tasks": null}"#
    let missing = try JSONDecoder().decode(SurfaceToday.self, from: Data(json.utf8))
    XCTAssertEqual(missing.wordText, "--")
    XCTAssertEqual(missing.definitionText, "--")
    XCTAssertEqual(SurfaceToday().wordText, "--")
    XCTAssertEqual(SurfaceToday(word: "  ", definition: "").definitionText, "--")

    let full = try JSONDecoder().decode(
      SurfaceToday.self,
      from: Data(
        #"{"date": "2026-03-11", "word": "Florble", "definition": " a kettle sound "}"#.utf8))
    XCTAssertEqual(full.wordText, "Florble")
    XCTAssertEqual(full.definitionText, "a kettle sound")
  }

  func testReloadAfterMidnightOrRetrySoon() {
    let midnightPlus5 = at(12, 0, 5)
    XCTAssertEqual(
      SurfaceToday.nextReload(after: at(11, 9), fetched: true, calendar: calendar), midnightPlus5)
    XCTAssertEqual(
      SurfaceToday.nextReload(after: at(11, 9), fetched: false, calendar: calendar), at(11, 9, 30))
    // A failed fetch late in the day still reloads for the new word, not half an hour later.
    XCTAssertEqual(
      SurfaceToday.nextReload(after: at(11, 23, 50), fetched: false, calendar: calendar),
      midnightPlus5)
    // A fetch just after midnight already has the new day's word.
    XCTAssertEqual(
      SurfaceToday.nextReload(after: at(12, 0, 5), fetched: true, calendar: calendar), at(13, 0, 5))
  }

  func testSavedNoteOnlyForAnEarlierDay() {
    let today = SurfaceToday(date: "2026-03-11", word: "Florble", definition: "a kettle sound")
    XCTAssertNil(today.savedNote(isCached: false, now: at(12, 9), calendar: calendar))
    XCTAssertNil(today.savedNote(isCached: true, now: at(11, 22), calendar: calendar))
    XCTAssertEqual(
      today.savedNote(isCached: true, now: at(12, 9), calendar: calendar), "Saved 2026-03-11")
    XCTAssertNil(SurfaceToday().savedNote(isCached: true, now: at(12, 9), calendar: calendar))
  }

  func testGoalLinesShowUpToThreeOrDashes() throws {
    let json =
      #"{"date": "2026-03-11", "goal": ["Learn to juggle", " ", "Paint the gate", "Fly a kite"]}"#
    let today = try JSONDecoder().decode(SurfaceToday.self, from: Data(json.utf8))
    XCTAssertEqual(today.goalLines, ["Learn to juggle", "Paint the gate", "Fly a kite"])
    XCTAssertEqual(SurfaceToday(goal: ["a", "b", "c", "d"]).goalLines, ["a", "b", "c"])
    XCTAssertEqual(SurfaceToday().goalLines, ["--"])
    XCTAssertEqual(SurfaceToday(goal: []).goalLines, ["--"])
    XCTAssertEqual(SurfaceToday(goal: ["", "  "]).goalLines, ["--"])
  }

  func testTaskRowsFitWithMoreCount() throws {
    let json = #"""
      {"date": "2026-03-11", "tasks": [
        {"text": "Feed the goldfish", "due": "2026-03-11", "source": "Planner.md"},
        {"text": " ", "due": "2026-03-11", "source": "Planner.md"},
        {"text": "Oil the hinge", "due": "2026-03-11", "source": "Planner.md"},
        {"text": "Fold the maps", "due": "2026-03-11", "source": "Planner.md"},
        {"text": "Wind the clock", "due": "2026-03-11", "source": "Planner.md"}]}
      """#
    let today = try JSONDecoder().decode(SurfaceToday.self, from: Data(json.utf8))
    XCTAssertEqual(today.tasks?.first?.source, "Planner.md")
    let now = at(11, 9)
    // Five tasks in four lines: three tasks and "+2 more"; a blank task shows "--".
    let four = try XCTUnwrap(today.taskList(fitting: 4, now: now, calendar: calendar))
    XCTAssertEqual(four.rows.map(\.text), ["Feed the goldfish", "--", "Oil the hinge"])
    XCTAssertEqual(four.more, 2)
    let five = try XCTUnwrap(today.taskList(fitting: 5, now: now, calendar: calendar))
    XCTAssertEqual(five.rows.count, 5)
    XCTAssertEqual(five.more, 0)
    // Nothing due is an empty list; tasks the server couldn't read are missing.
    XCTAssertEqual(
      SurfaceToday(tasks: []).taskList(fitting: 4, now: now, calendar: calendar),
      TaskList(rows: [], more: 0))
    XCTAssertNil(SurfaceToday().taskList(fitting: 4, now: now, calendar: calendar))
  }

  func testOverdueMeansBeforeTodayOnThePhone() throws {
    let today = SurfaceToday(
      date: "2026-03-11",
      tasks: [
        SurfaceTask(text: "Return the atlas", due: "2026-03-10"),
        SurfaceTask(text: "Feed the goldfish", due: "2026-03-11"),
      ])
    let live = try XCTUnwrap(today.taskList(fitting: 4, now: at(11, 9), calendar: calendar))
    XCTAssertEqual(live.rows.map(\.overdue), [true, false])
    // The same copy, still cached the next morning: both are overdue now.
    let saved = try XCTUnwrap(today.taskList(fitting: 4, now: at(12, 9), calendar: calendar))
    XCTAssertEqual(saved.rows.map(\.overdue), [true, true])
    XCTAssertEqual(SurfaceToday.day(of: at(12, 0, 1), calendar: calendar), "2026-03-12")
  }

  func testTasksReloadEvery45MinutesAndAfterMidnight() {
    XCTAssertEqual(
      SurfaceToday.nextTasksReload(after: at(11, 9), calendar: calendar), at(11, 9, 45))
    XCTAssertEqual(
      SurfaceToday.nextTasksReload(after: at(11, 23, 40), calendar: calendar), at(12, 0, 5))
    // 45 minutes apart all day, plus the midnight reload: at most 33 in a day.
    var reloads = 0
    var next = at(11, 0, 5)
    while next < at(12, 0, 5) {
      next = SurfaceToday.nextTasksReload(after: next, calendar: calendar)
      reloads += 1
    }
    XCTAssertLessThanOrEqual(reloads, 33)
  }
}
