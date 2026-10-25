import XCTest

/// S-004: log the prefilled set in one tap, adjust with steppers, switch to bodyweight, undo.
final class SetLoggerUITests: XCTestCase {
  @MainActor
  func testLogSetInOneTapAdjustAndUndo() {
    continueAfterFailure = false
    let app = UITestApp.launch()

    // Step 1: Start Day 1. The Log card is prefilled: the seed's 45 lb bar and 6 reps.
    let card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card on Home")
    card.tap()
    let start = app.element("workout.today.start")
    XCTAssertTrue(start.waitForExistence(timeout: 10), "no Start on the Workout screen")
    start.tap()
    let weight = app.element("workout.logger.weight")
    let reps = app.element("workout.logger.repCount")
    let set = app.element("workout.logger.set")
    XCTAssertTrue(weight.waitForExistence(timeout: 10), "the Log card did not open")
    XCTAssertEqual(app.element("workout.logger.exercise").label, "Bench press")
    XCTAssertEqual(set.label, "Set 1 of 3")
    XCTAssertEqual(weight.label, "45 lb")
    XCTAssertEqual(reps.label, "6")
    XCTAssertFalse(app.element("workout.logger.logged.0").exists, "a set is logged already")
    saveScreenshot("s004-prefilled", of: app)

    // Step 2: one tap logs it; the card moves to set 2 with the same numbers.
    app.element("workout.logger.log").tap()
    let first = app.element("workout.logger.logged.0")
    XCTAssertTrue(first.waitForExistence(timeout: 5), "the logged set is not shown")
    XCTAssertTrue(first.label.contains("45 lb x 6"), first.label)
    XCTAssertEqual(set.label, "Set 2 of 3")
    XCTAssertEqual(weight.label, "45 lb")
    XCTAssertEqual(reps.label, "6")
    saveScreenshot("s004-logged", of: app)

    // Step 3: + on weight (5 lb step) and - on reps, no keyboard, then Log.
    app.element("workout.logger.weight.plus").tap()
    app.element("workout.logger.repCount.minus").tap()
    XCTAssertEqual(weight.label, "50 lb")
    XCTAssertEqual(reps.label, "5")
    XCTAssertEqual(app.keyboards.count, 0, "a keyboard appeared")
    app.element("workout.logger.log").tap()
    let second = app.element("workout.logger.logged.1")
    XCTAssertTrue(second.waitForExistence(timeout: 5), "the second set is not shown")
    XCTAssertTrue(second.label.contains("50 lb x 5"), second.label)
    XCTAssertEqual(set.label, "Set 3 of 3")

    // Step 4: the bodyweight toggle shows BW instead of a weight.
    app.element("workout.logger.bodyweight").tap()
    XCTAssertEqual(weight.label, "BW")

    // Step 5: Undo removes only the last set and the card returns to it.
    app.element("workout.logger.undo").tap()
    XCTAssertTrue(second.waitForNonExistence(timeout: 5), "the last set was not removed")
    XCTAssertTrue(first.exists, "undo removed more than the last set")
    XCTAssertEqual(set.label, "Set 2 of 3")
    XCTAssertEqual(weight.label, "50 lb")
    XCTAssertEqual(reps.label, "5")
    saveScreenshot("s004-undone", of: app)
  }
}
