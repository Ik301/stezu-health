import XCTest

/// S-006: logging a set starts the rest by itself; +15 s and -15 s move it; Skip ends it.
final class RestTimerUITests: XCTestCase {
  @MainActor
  func testRestStartsAfterLogAndAdjusts() {
    continueAfterFailure = false
    let app = UITestApp.launch()
    let card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card on Home")
    card.tap()
    let start = app.element("workout.today.start")
    XCTAssertTrue(start.waitForExistence(timeout: 10), "no Start on the Workout screen")
    start.tap()
    let log = app.element("workout.logger.log")
    XCTAssertTrue(log.waitForExistence(timeout: 10), "the Log card did not open")
    let countdown = app.element("workout.rest.countdown")
    XCTAssertFalse(countdown.exists, "a rest runs before any set is logged")

    // Step 1: one tap on Log, and the rest counts down from bench press's 150 s seed rest.
    log.tap()
    XCTAssertTrue(countdown.waitForExistence(timeout: 5), "no rest countdown after Log")
    let startedAt = countdown.value as? String
    XCTAssertNotNil(startedAt)
    let running = seconds(countdown.label)
    XCTAssertTrue((130...150).contains(running), countdown.label)
    saveScreenshot("s006-rest-running", of: app)

    // Step 2: +15 s lengthens it and -15 s shortens it again; the start time is kept.
    app.element("workout.rest.plus").tap()
    let longer = seconds(countdown.label)
    XCTAssertTrue(longer > running + 5 && longer <= running + 15, countdown.label)
    XCTAssertEqual(countdown.value as? String, startedAt, "+15 s moved the start")
    saveScreenshot("s006-rest-adjusted", of: app)
    app.element("workout.rest.minus").tap()
    let shorter = seconds(countdown.label)
    XCTAssertTrue(shorter < longer - 5, countdown.label)
    XCTAssertEqual(countdown.value as? String, startedAt, "-15 s moved the start")

    // Skip: the countdown goes away.
    app.element("workout.rest.skip").tap()
    XCTAssertTrue(countdown.waitForNonExistence(timeout: 5), "Skip left the countdown")
  }

  /// "2:30" as 150; -1 when the label is not m:ss.
  private func seconds(_ label: String) -> Int {
    let parts = label.split(separator: ":").compactMap { Int($0) }
    return parts.count == 2 ? parts[0] * 60 + parts[1] : -1
  }
}
