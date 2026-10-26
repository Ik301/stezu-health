import XCTest

/// S-009: a workout in progress survives a relaunch. The Workout screen offers Resume in place
/// of the black card, and one tap opens the logger on the same exercise with both sets.
final class SessionResumeUITests: XCTestCase {
  @MainActor
  func testUnfinishedSessionResumesAfterRelaunch() {
    continueAfterFailure = false

    // Step 1: a fresh persisted store; start Day 1 and log two sets.
    var app = UITestApp.launch(persist: true, reset: true)
    var card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card on Home")
    card.tap()
    let start = app.element("workout.today.start")
    XCTAssertTrue(start.waitForExistence(timeout: 10), "no Start on the Workout screen")
    start.tap()
    let log = app.element("workout.logger.log")
    XCTAssertTrue(log.waitForExistence(timeout: 10), "the Log card did not open")
    XCTAssertEqual(app.element("workout.logger.exercise").label, "Bench press")
    log.tap()
    XCTAssertTrue(app.element("workout.logger.logged.0").waitForExistence(timeout: 5))
    log.tap()
    XCTAssertTrue(app.element("workout.logger.logged.1").waitForExistence(timeout: 5))

    // Step 2: terminate and relaunch with the same store. Resume replaces the black card.
    app.terminate()
    app = UITestApp.launch(persist: true)
    card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card after relaunch")
    card.tap()
    let resume = app.element("workout.resume")
    XCTAssertTrue(resume.waitForExistence(timeout: 10), "no Resume on the Workout screen")
    XCTAssertFalse(app.element("workout.today.start").exists, "the black card is still shown")
    XCTAssertEqual(app.element("workout.resume.name").label, "Day 1 Push")
    XCTAssertEqual(app.element("workout.resume.sets").label, "2 sets logged")
    saveScreenshot("s009-resume-card", of: app)

    // Step 3: one tap; the logger is on the same exercise with both sets logged.
    resume.tap()
    let exercise = app.element("workout.logger.exercise")
    XCTAssertTrue(exercise.waitForExistence(timeout: 10), "the logger did not open")
    XCTAssertEqual(exercise.label, "Bench press")
    XCTAssertEqual(app.element("workout.logger.set").label, "Set 3 of 3")
    let first = app.element("workout.logger.logged.0")
    let second = app.element("workout.logger.logged.1")
    XCTAssertTrue(first.waitForExistence(timeout: 5), "the first set was not kept")
    XCTAssertTrue(second.exists, "the second set was not kept")
    XCTAssertTrue(first.label.contains("45 lb x 6"), first.label)
    XCTAssertTrue(second.label.contains("45 lb x 6"), second.label)
    saveScreenshot("s009-resumed", of: app)
  }
}
