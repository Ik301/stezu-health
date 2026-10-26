import XCTest

/// S-035: a program file's add-on block (Abs) is not a day on Workout. While a workout runs, the
/// logger shows "+ Abs"; one tap appends its exercises after the day's own, and it stays one
/// session. The "program-addon" fixture is generic: Push and Pull with one exercise each, and
/// Abs with Cable crunch and Hanging leg raise (D-034).
final class WorkoutLoggerUITests: XCTestCase {
  /// Scrolls until the element can be tapped, then taps it.
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
  func testAddOnAppendsToCurrentWorkout() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "program-addon")
    let card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card on Home")
    card.tap()
    XCTAssertTrue(app.element("workout.today.name").waitForExistence(timeout: 10))

    // Step 1: after the import the Workout screen lists only the two days.
    tap("workout.import", in: app)
    let alert = app.alerts.firstMatch
    XCTAssertTrue(alert.waitForExistence(timeout: 10), "no Replace confirmation")
    alert.buttons["Replace"].firstMatch.tap()
    let message = app.element("workout.import.message")
    XCTAssertTrue(message.waitForExistence(timeout: 10), "the import showed no result")
    app.swipeDown()
    XCTAssertEqual(app.element("workout.today.name").label, "Push")
    XCTAssertTrue(app.element("workout.template.pull").exists, "Pull is not listed")
    XCTAssertFalse(app.element("workout.template.abs").exists, "the add-on is listed as a day")
    XCTAssertFalse(app.element("workout.template.push").exists, "Push is listed twice")

    // Step 2: the running workout offers "+ Abs" below the day's exercise.
    tap("workout.today.start", in: app, up: false)
    let exercise = app.element("workout.logger.exercise")
    XCTAssertTrue(exercise.waitForExistence(timeout: 10), "the logger did not open")
    XCTAssertEqual(exercise.label, "Bench press")
    let addOn = app.element("workout.logger.addon.abs")
    XCTAssertTrue(addOn.waitForExistence(timeout: 5), "no add-on button")
    XCTAssertEqual(addOn.label, "+ Abs")
    saveScreenshot("s035-addon-button", of: app)

    // One tap appends Abs and the button goes; the card finishes the day's exercise first.
    tap("workout.logger.addon.abs", in: app)
    let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: addOn)
    wait(for: [gone], timeout: 5)
    XCTAssertEqual(exercise.label, "Bench press", "the add-on jumped ahead of the day")
    tap("workout.logger.log", in: app, up: false)
    XCTAssertEqual(exercise.label, "Cable crunch", "the add-on does not follow the day")
    XCTAssertEqual(app.element("workout.logger.set").label, "Set 1 of 2")
    XCTAssertEqual(app.element("workout.logger.weight").label, "30 lb")
    tap("workout.logger.log", in: app, up: false)
    XCTAssertTrue(app.element("workout.logger.logged.0").waitForExistence(timeout: 5))
    XCTAssertEqual(app.element("workout.logger.set").label, "Set 2 of 2")
    XCTAssertTrue(app.element("workout.rest.countdown").exists, "no rest after the add-on set")
    saveScreenshot("s035-addon-appended", of: app)

    // Step 3: one Finish, one session under Push with the add-on exercise; the unlogged
    // Hanging leg raise is left out.
    tap("workout.logger.finish", in: app, up: false)
    let row = app.element("workout.session.0")
    XCTAssertTrue(row.waitForExistence(timeout: 10), "the finished session is not shown")
    XCTAssertTrue(row.label.hasPrefix("Push"), row.label)
    XCTAssertTrue(row.label.hasSuffix("2 sets"), row.label)
    XCTAssertFalse(app.element("workout.session.1").exists, "the add-on made a second session")

    // Step 6: History shows one session containing the add-on exercise.
    tap("workout.history", in: app, up: false)
    let session = app.element("history.session.0.0")
    XCTAssertTrue(session.waitForExistence(timeout: 10), "no session in History")
    XCTAssertFalse(app.element("history.session.0.1").exists, "two sessions in History")
    session.tap()
    let first = app.element("history.exercise.0")
    XCTAssertTrue(first.waitForExistence(timeout: 10), "the session has no exercises")
    XCTAssertEqual(first.label, "Bench press")
    XCTAssertEqual(app.element("history.exercise.1").label, "Cable crunch")
    XCTAssertEqual(app.element("history.exercise.1.sets").label, "30 x 10")
    XCTAssertFalse(app.element("history.exercise.2").exists, "an unlogged exercise was saved")
  }
}
