import XCTest

/// S-036: Next is the day after the last finished session, whatever day that was (D-089); any
/// day starts off schedule in one tap; a session finished under 12 hours ago can be continued
/// in one tap and is saved again under the same id (D-090).
final class WorkoutRotationUITests: XCTestCase {
  @MainActor
  func testNextAdvancesAndOffScheduleAndContinue() {
    continueAfterFailure = false
    // Step 7: a fresh persisted store whose last finished session is Day 1, two days ago.
    let app = UITestApp.launch(scenario: "rotation", persist: true, reset: true)
    let card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card on Home")
    XCTAssertTrue(wait(card, "label CONTAINS %@", "Next: Day 2 Pull,"), card.label)

    // Steps 1 and 2: the black card says the same day as Home. Too old to continue.
    card.tap()
    let name = app.element("workout.today.name")
    XCTAssertTrue(name.waitForExistence(timeout: 10), "no black card")
    XCTAssertEqual(name.label, "Day 2 Pull")
    XCTAssertFalse(app.element("workout.continue").exists, "a 2-day-old session offers Continue")

    // Step 3: Day 3 off schedule from its own row, one tap; log a set and Finish.
    tap("workout.template.day-3", in: app)
    let exercise = app.element("workout.logger.exercise")
    let log = app.element("workout.logger.log")
    XCTAssertTrue(log.waitForExistence(timeout: 10), "the Log card did not open")
    XCTAssertEqual(exercise.label, "Back squat")
    log.tap()
    XCTAssertTrue(app.element("workout.logger.logged.0").waitForExistence(timeout: 5))
    app.element("workout.logger.finish").tap()
    XCTAssertTrue(app.element("workout.summary.done").waitForExistence(timeout: 10), "no summary")
    app.element("workout.summary.done").tap()  // S-044: Finish opens the summary; Done returns

    // Next is the day after Day 3; the program is unchanged; Continue is offered.
    XCTAssertTrue(name.waitForExistence(timeout: 10), "the logger did not close")
    XCTAssertTrue(wait(name, "label == %@", "Day 4 Upper"), name.label)
    XCTAssertTrue(app.element("workout.template.day-2").exists, "the program changed")
    XCTAssertTrue(app.element("workout.template.day-3").exists, "the program changed")
    saveScreenshot("s036-next-advanced", of: app)
    let row = app.element("workout.continue")
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no Continue row")
    XCTAssertEqual(row.label, "Continue Day 3 Legs, 1 set")
    saveScreenshot("s036-continue-row", of: app)

    // Step 2: Home says the same Next.
    app.element("nav.home").tap()
    XCTAssertTrue(card.waitForExistence(timeout: 10), "not back on Home")
    XCTAssertTrue(wait(card, "label CONTAINS %@", "Next: Day 4 Upper,"), card.label)
    card.tap()

    // Step 4: Continue, one tap: the same session with its set; a new set appends.
    tap("workout.continue", in: app, up: false)
    XCTAssertTrue(log.waitForExistence(timeout: 10), "Continue did not open the logger")
    XCTAssertEqual(exercise.label, "Back squat")
    XCTAssertTrue(app.element("workout.logger.logged.0").exists, "the session's set is not shown")
    XCTAssertEqual(app.element("workout.logger.set").label, "Set 2 of 3")
    log.tap()
    XCTAssertTrue(app.element("workout.logger.logged.1").waitForExistence(timeout: 5))
    app.element("workout.logger.finish").tap()
    XCTAssertTrue(app.element("workout.summary.done").waitForExistence(timeout: 10), "no summary")
    app.element("workout.summary.done").tap()  // S-044: Finish opens the summary; Done returns

    // Step 5: one session with both sets, here and in History; Next is unchanged.
    let session = app.element("workout.session.0")
    XCTAssertTrue(session.waitForExistence(timeout: 10), "the session is not shown")
    XCTAssertTrue(wait(session, "label BEGINSWITH %@", "Day 3 Legs   2 sets"), session.label)
    XCTAssertFalse(
      app.element("workout.session.1").exists
        && app.element("workout.session.1").label.hasPrefix("Day 3"), "a second Day 3 session")
    XCTAssertEqual(name.label, "Day 4 Upper")
    tap("workout.history", in: app)
    let newest = app.element("history.session.0.0")
    XCTAssertTrue(newest.waitForExistence(timeout: 10), "no session in History")
    XCTAssertTrue(newest.label.hasPrefix("Day 3 Legs"), newest.label)
    XCTAssertTrue(newest.label.hasSuffix("2 sets"), newest.label)
    for index in 1..<3 {
      let other = app.element("history.session.0.\(index)")
      XCTAssertFalse(other.exists && other.label.hasPrefix("Day 3"), "Day 3 is in History twice")
    }
    newest.tap()
    let sets = app.element("history.exercise.0.sets")
    XCTAssertTrue(sets.waitForExistence(timeout: 10), "the session did not open")
    XCTAssertEqual(sets.label, "45 x 5, 45 x 5")
    XCTAssertTrue(app.element("history.session.continue").exists, "no Continue in History")
  }

  @MainActor
  private func tap(_ id: String, in app: XCUIApplication, up: Bool = true) {
    let element = app.element(id)
    XCTAssertTrue(element.waitForExistence(timeout: 10), "no \(id)")
    for _ in 0..<3 where !element.isHittable {
      if up { app.swipeUp() } else { app.swipeDown() }
    }
    element.tap()
  }

  @MainActor
  private func wait(_ element: XCUIElement, _ format: String, _ text: String) -> Bool {
    let match = NSPredicate(format: format, text)
    return XCTWaiter().wait(for: [expectation(for: match, evaluatedWith: element)], timeout: 15)
      == .completed
  }
}
