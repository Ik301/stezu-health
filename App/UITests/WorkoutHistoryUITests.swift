import XCTest

/// S-010: History groups the synthetic sessions (Day 1 7 days ago, Day 2 2 days ago) into
/// Monday-to-Sunday weeks, newest first, with working-set counts and no empty weeks. A session
/// opens its sets as weight x reps; an exercise opens its past sessions, newest first.
final class WorkoutHistoryUITests: XCTestCase {
  @MainActor
  func testWeeklyHistoryAndSessionDetail() {
    continueAfterFailure = false
    // Step 1: on Workout, tap History.
    let app = UITestApp.launch(scenario: "workout-history")
    let card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card on Home")
    card.tap()
    let history = app.element("workout.history")
    XCTAssertTrue(history.waitForExistence(timeout: 10), "no History on the Workout screen")
    history.tap()

    // Step 2: the two sessions share a Monday-to-Sunday week only when today is a Monday or a
    // Tuesday; work out which from the same synthetic dates.
    var calendar = Calendar.current
    calendar.firstWeekday = 2
    let mondays = [2, 7].map { days -> Date in
      let date = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
      return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }
    let expected =
      mondays[0] == mondays[1] ? ["6 working sets"] : ["3 working sets", "3 working sets"]
    XCTAssertTrue(app.element("history.week.0").waitForExistence(timeout: 10), "no weeks")
    for (index, sets) in expected.enumerated() {
      let week = app.element("history.week.\(index)")
      XCTAssertTrue(week.label.hasPrefix("Mon"), week.label)
      XCTAssertTrue(week.label.contains("Sun"), week.label)
      XCTAssertEqual(app.element("history.week.\(index).sets").label, sets)
    }
    XCTAssertFalse(app.element("history.week.\(expected.count)").exists, "an extra week row")
    let newest = app.element("history.session.0.0")
    XCTAssertTrue(newest.exists, "no session row in the newest week")
    XCTAssertTrue(newest.label.contains("3 sets"), newest.label)
    saveScreenshot("s010-history", of: app)

    // Step 3: the newest session (Day 2) shows its exercises and sets as weight x reps.
    newest.tap()
    let bench = app.element("history.exercise.0")
    XCTAssertTrue(bench.waitForExistence(timeout: 10), "the session did not open")
    XCTAssertEqual(bench.label, "Bench press")
    XCTAssertEqual(app.element("history.exercise.0.sets").label, "65 x 5")
    XCTAssertEqual(app.element("history.exercise.1").label, "Overhead press")
    XCTAssertEqual(app.element("history.exercise.1.sets").label, "40 x 10")
    XCTAssertEqual(app.element("history.exercise.2.sets").label, "70 x 8")
    saveScreenshot("s010-session", of: app)

    // An exercise opens its past sessions, newest first.
    bench.tap()
    let latest = app.element("history.past.0")
    XCTAssertTrue(latest.waitForExistence(timeout: 10), "the exercise did not open")
    XCTAssertTrue(latest.label.contains("65 x 5"), latest.label)
    let earlier = app.element("history.past.1")
    XCTAssertTrue(earlier.label.contains("60 x 8, 60 x 8, 60 x 7"), earlier.label)
    XCTAssertFalse(app.element("history.past.2").exists, "a session without bench press")
  }
}
