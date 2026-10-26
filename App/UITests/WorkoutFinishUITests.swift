import XCTest

/// S-008: Finish with no sets discards the session; Finish after a set closes the logger, the
/// week's numbers count it, and its row says the fake HealthStore took the write.
final class WorkoutFinishUITests: XCTestCase {
  @MainActor
  func testFinishSavesAndWritesToHealth() {
    continueAfterFailure = false
    let app = UITestApp.launch()
    let card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card on Home")
    card.tap()
    let start = app.element("workout.today.start")
    let sessions = app.element("workout.week.sessions")
    let sets = app.element("workout.week.sets")
    let row = app.element("workout.session.0")
    let finish = app.element("workout.logger.finish")
    XCTAssertTrue(start.waitForExistence(timeout: 10), "no Start on the Workout screen")
    XCTAssertEqual(sessions.label, "--")

    // Step 4: Finish with no sets discards the session; nothing is counted.
    start.tap()
    XCTAssertTrue(finish.waitForExistence(timeout: 10), "no Finish in the logger")
    finish.tap()
    XCTAssertTrue(start.waitForExistence(timeout: 10), "the logger did not close")
    XCTAssertFalse(row.exists, "an empty session was kept")
    XCTAssertEqual(sessions.label, "--")
    XCTAssertEqual(sets.label, "--")

    // Step 1: log one set and tap Finish, with no confirmation.
    start.tap()
    let log = app.element("workout.logger.log")
    XCTAssertTrue(log.waitForExistence(timeout: 10), "the Log card did not open")
    log.tap()
    XCTAssertTrue(app.element("workout.logger.logged.0").waitForExistence(timeout: 5))
    finish.tap()
    XCTAssertTrue(row.waitForExistence(timeout: 10), "the finished session is not shown")
    XCTAssertTrue(start.exists, "the logger did not close")
    XCTAssertTrue(row.label.contains("1 set"), row.label)
    XCTAssertEqual(sessions.label, "1")
    XCTAssertEqual(sets.label, "1")
    saveScreenshot("s008-finished", of: app)

    // Step 2: the fake HealthStore took the write, so the row says In Health.
    let health = app.element("workout.session.0.health")
    XCTAssertTrue(health.waitForExistence(timeout: 5), "no Health status on the row")
    XCTAssertEqual(health.label, "In Health")
    saveScreenshot("s008-in-health", of: app)
  }
}
