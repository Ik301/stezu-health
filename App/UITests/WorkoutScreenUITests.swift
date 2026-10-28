import XCTest

/// S-045: the Workout screen per design/system/walkthroughs/workout.html. Launches with the
/// generic "workout-history" fixture: a Day 1 session 7 days ago and a Day 2 session 2 days ago,
/// none this week from the store, made-up numbers (D-034).
final class WorkoutScreenUITests: XCTestCase {
  @MainActor
  func testWeekCardNextLabelAndLastDone() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "workout-history")
    let card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card on Home")
    card.tap()

    // The black card is labelled "Next in your program"; This week shows its dots.
    let label = app.element("workout.today.label")
    XCTAssertTrue(label.waitForExistence(timeout: 10), "no black card label")
    XCTAssertEqual(label.label, "Next in your program")
    XCTAssertEqual(app.element("workout.today.name").label, "Day 1 Push")
    XCTAssertTrue(app.element("workout.week.dots").exists, "no day dots on This week")
    XCTAssertTrue(app.element("workout.week.dots").label.hasPrefix("0 of "))
    XCTAssertEqual(app.element("workout.week.sessions").label, "--")
    XCTAssertEqual(app.element("workout.week.sets").label, "--")
    XCTAssertTrue(app.element("workout.history").exists, "History left the TopBar")

    // Other days say when each was last done; each still starts in one tap.
    let pull = app.element("workout.template.day-2")
    XCTAssertTrue(pull.exists, "no Day 2 row")
    XCTAssertTrue(pull.label.contains("2 days ago"), pull.label)
    let legs = app.element("workout.template.day-3")
    XCTAssertTrue(legs.exists, "no Day 3 row")
    XCTAssertTrue(legs.label.contains("not done yet"), legs.label)
    XCTAssertTrue(app.element("workout.template.empty").exists, "no Empty workout row")
    saveScreenshot("s045-workout-screen", of: app)

    // Start, log a set, Finish: the summary has the template as title, the date and time line,
    // and the In Health tag.
    app.element("workout.today.start").tap()
    let log = app.element("workout.logger.log")
    XCTAssertTrue(log.waitForExistence(timeout: 10), "the logger did not open")
    log.tap()
    app.element("workout.logger.finish").tap()
    let when = app.element("workout.summary.when")
    XCTAssertTrue(when.waitForExistence(timeout: 10), "no date line on the summary")
    let line = NSPredicate(format: "label MATCHES %@", ".+, [0-9]{2}:[0-9]{2} to [0-9]{2}:[0-9]{2}")
    XCTAssertTrue(line.evaluate(with: when), when.label)
    XCTAssertEqual(app.element("screen.workout.title").label, "Day 1 Push")
    XCTAssertTrue(app.element("workout.summary.undo").exists, "no Undo at the top")
    XCTAssertLessThan(
      app.element("workout.summary.undo").frame.minY, when.frame.minY, "Undo is not on top")
    let health = app.element("workout.summary.health")
    let inHealth = expectation(
      for: NSPredicate(format: "label == %@", "In Health"), evaluatedWith: health)
    wait(for: [inHealth], timeout: 10)
    saveScreenshot("s045-summary", of: app)

    // Done returns to the Workout screen.
    app.element("workout.summary.done").tap()
    XCTAssertTrue(app.element("workout.week.dots").waitForExistence(timeout: 10))
    XCTAssertEqual(app.element("screen.workout.title").label, "Workout")
  }
}
