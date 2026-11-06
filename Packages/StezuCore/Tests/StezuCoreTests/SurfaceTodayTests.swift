import Foundation
import StezuCore
import XCTest

/// What the home-screen widgets draw from GET /surface/today (S-060). Words are synthetic.
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
}
