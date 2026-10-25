import XCTest

/// S-005: each set shows the last session's numbers, from the same template first, and the Log
/// card is prefilled from them. A first-ever exercise shows "--" and cannot log until a weight
/// or bodyweight is chosen.
final class LastSessionUITests: XCTestCase {
  @MainActor
  func testLastNumbersFromSameTemplate() {
    continueAfterFailure = false
    // Step 1: synthetic history: Day 1 7 days ago (bench 60 x 8), Day 2 2 days ago (bench
    // 65 x 5 and the only overhead press, 40 x 10).
    let app = UITestApp.launch(scenario: "workout-history")

    // Step 2: start Day 1. Bench shows the Day 1 numbers, not the newer Day 2 ones.
    let card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card on Home")
    card.tap()
    let start = app.element("workout.today.start")
    XCTAssertTrue(start.waitForExistence(timeout: 10), "no Start on the Workout screen")
    start.tap()
    let exercise = app.element("workout.logger.exercise")
    let last = app.element("workout.logger.last")
    let weight = app.element("workout.logger.weight")
    let reps = app.element("workout.logger.repCount")
    let log = app.element("workout.logger.log")
    XCTAssertTrue(last.waitForExistence(timeout: 10), "no last numbers on the Log card")
    XCTAssertEqual(exercise.label, "Bench press")
    XCTAssertEqual(last.label, "Last 60 x 8, 7d ago")

    // Step 3: the Log card is prefilled from those numbers.
    XCTAssertEqual(weight.label, "60 lb")
    XCTAssertEqual(reps.label, "8")
    saveScreenshot("s005-last-numbers", of: app)

    // The logged row keeps its last numbers; set 3 shows the last session's set 3.
    log.tap()
    let first = app.element("workout.logger.logged.0")
    XCTAssertTrue(first.waitForExistence(timeout: 5), "the logged set is not shown")
    XCTAssertTrue(first.label.contains("Last 60 x 8, 7d ago"), first.label)
    log.tap()
    XCTAssertEqual(last.label, "Last 60 x 7, 7d ago")
    log.tap()

    // No Day 1 session had overhead press, so the Day 2 one is used.
    XCTAssertEqual(exercise.label, "Overhead press")
    XCTAssertEqual(last.label, "Last 40 x 10, 2d ago")
    XCTAssertEqual(weight.label, "40 lb")
    XCTAssertEqual(reps.label, "10")
    log.tap()
    log.tap()
    log.tap()

    // Step 4: never done before: "--" and Log stays off until bodyweight or a weight is set.
    XCTAssertEqual(exercise.label, "Incline dumbbell press")
    XCTAssertEqual(last.label, "Last --")
    XCTAssertEqual(weight.label, "--")
    XCTAssertFalse(log.isEnabled, "Log is on without a weight")
    saveScreenshot("s005-first-ever", of: app)
    app.element("workout.logger.weight.plus").tap()
    XCTAssertEqual(weight.label, "5 lb")
    XCTAssertTrue(log.isEnabled, "Log is still off after a weight was set")
  }
}
