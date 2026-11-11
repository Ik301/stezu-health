import XCTest

/// Fix (D-158): an exercise from Add exercise gets the sets and reps Isaac chooses, when it is
/// added and later from the card's menu. Default launch: no history (D-034).
final class AddedExerciseSetsUITests: XCTestCase {
  /// Scrolls until the element can be tapped, then taps it.
  @MainActor
  private func tap(_ id: String, in app: XCUIApplication, up: Bool = true, times: Int = 1) {
    let element = app.element(id)
    XCTAssertTrue(element.waitForExistence(timeout: 10), "no \(id)")
    for _ in 0..<3 where !element.isHittable {
      if up { app.swipeUp() } else { app.swipeDown() }
    }
    for _ in 0..<times { element.tap() }
  }

  @MainActor
  func testAddedExerciseGetsChosenSetsAndReps() {
    continueAfterFailure = false
    let app = UITestApp.launch()
    let card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card on Home")
    card.tap()
    tap("workout.template.empty", in: app)
    tap("workout.logger.addExercise", in: app)

    // A pick opens Sets and reps at 3 x 8-12; Cancel goes back to the library.
    let search = app.element("workout.library.search")
    XCTAssertTrue(search.waitForExistence(timeout: 10), "the Exercises library did not open")
    search.tap()
    search.typeText("fly")
    tap("workout.library.row.dumbbell-fly", in: app)
    let summary = app.element("workout.shape.summary")
    XCTAssertTrue(summary.waitForExistence(timeout: 5), "Sets and reps did not open")
    XCTAssertEqual(app.element("workout.shape.title").label, "Dumbbell fly")
    XCTAssertEqual(summary.label, "3 x 8-12")
    tap("workout.shape.cancel", in: app)
    XCTAssertTrue(search.waitForExistence(timeout: 5), "Cancel did not go back to the library")
    search.tap()
    search.typeText("fly")
    tap("workout.library.row.dumbbell-fly", in: app)

    // Steppers only: 5 sets, reps from 10 to 10, a fixed 10.
    tap("workout.shape.sets.plus", in: app, times: 2)
    XCTAssertEqual(app.element("workout.shape.sets").label, "5")
    tap("workout.shape.repsLow.plus", in: app, times: 2)
    XCTAssertEqual(summary.label, "5 x 10-12")
    tap("workout.shape.repsHigh.minus", in: app, times: 2)
    XCTAssertEqual(summary.label, "5 x 10")
    saveScreenshot("fix-added-sets-reps", of: app)
    tap("workout.shape.save", in: app)

    // The card has the chosen shape, prefilled at the low end.
    let exercise = app.element("workout.logger.exercise")
    XCTAssertTrue(
      exercise.waitForExistence(timeout: 10) && exercise.label == "Dumbbell fly",
      "the pick is not on the card: \(exercise.label)")
    XCTAssertEqual(app.element("workout.logger.set").label, "Set 1 of 5")
    XCTAssertEqual(app.element("workout.logger.reps").label, "10 reps")
    XCTAssertEqual(app.element("workout.logger.repCount").label, "10")

    // Later, the card's menu: Sets and reps opens at the slot's own shape; one set fewer.
    let menu = app.element("workout.logger.menu")
    XCTAssertTrue(menu.waitForExistence(timeout: 5), "no exercise menu on the Log card")
    menu.tap()
    let edit = app.element("workout.logger.setsReps")
    if edit.waitForExistence(timeout: 3) { edit.tap() } else { app.buttons["Sets and reps"].tap() }
    XCTAssertTrue(summary.waitForExistence(timeout: 5), "Sets and reps did not open")
    XCTAssertEqual(summary.label, "5 x 10")
    tap("workout.shape.sets.minus", in: app)
    XCTAssertEqual(summary.label, "4 x 10")
    tap("workout.shape.save", in: app)
    let set = app.element("workout.logger.set")
    XCTAssertTrue(
      set.waitForExistence(timeout: 10) && set.label == "Set 1 of 4", "card reads \(set.label)")
    saveScreenshot("fix-added-sets-reps-card", of: app)
  }
}
