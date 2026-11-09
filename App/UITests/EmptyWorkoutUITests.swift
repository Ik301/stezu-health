import XCTest

/// Bug fix: an Empty workout starts with no exercise, so the logger needs Add exercise to log
/// anything. Default launch: no history, so the added exercise starts at "--" (D-034).
final class EmptyWorkoutUITests: XCTestCase {
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
  func testEmptyWorkoutAddExerciseThenLogSet() {
    continueAfterFailure = false
    let app = UITestApp.launch()
    let card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card on Home")
    card.tap()

    // Workout > Empty workout: a logger with no exercise, Log off, and Add exercise.
    tap("workout.template.empty", in: app)
    let exercise = app.element("workout.logger.exercise")
    XCTAssertTrue(exercise.waitForExistence(timeout: 10), "the logger did not open")
    XCTAssertEqual(exercise.label, "No exercises")
    XCTAssertFalse(app.element("workout.logger.log").isEnabled, "Log is on with no exercise")
    XCTAssertTrue(app.element("workout.logger.addExercise").exists, "no Add exercise")
    saveScreenshot("fix-empty-workout", of: app)

    // Add exercise opens the library; a pick puts the exercise on the card.
    tap("workout.logger.addExercise", in: app)
    let search = app.element("workout.library.search")
    XCTAssertTrue(search.waitForExistence(timeout: 10), "the Exercises library did not open")
    search.tap()
    search.typeText("fly")
    let fly = app.element("workout.library.row.dumbbell-fly")
    XCTAssertTrue(fly.waitForExistence(timeout: 5), "no Dumbbell fly row")
    fly.tap()
    XCTAssertTrue(
      exercise.waitForExistence(timeout: 10) && exercise.label == "Dumbbell fly",
      "the pick is not on the card: \(exercise.label)")
    XCTAssertEqual(app.element("workout.logger.set").label, "Set 1 of 3")
    XCTAssertEqual(app.element("workout.logger.reps").label, "8-12 reps")
    XCTAssertEqual(app.element("workout.logger.weight").label, "--")
    XCTAssertEqual(app.element("workout.logger.progress").label, "Exercise 1 of 1")

    // One weight step, Log: the set is listed under the card and the card moves to set 2.
    tap("workout.logger.weight.plus", in: app, up: false)
    tap("workout.logger.log", in: app, up: false)
    let logged = app.element("workout.logger.logged.0")
    XCTAssertTrue(logged.waitForExistence(timeout: 5), "the logged set is not listed")
    XCTAssertTrue(logged.label.hasPrefix("Set 1   5 lb x 8"), logged.label)
    XCTAssertEqual(app.element("workout.logger.set").label, "Set 2 of 3")
    saveScreenshot("fix-empty-workout-logged", of: app)

    // Finish keeps it: the summary lists the added exercise.
    app.element("workout.logger.finish").tap()
    let first = app.element("workout.summary.exercise.0")
    XCTAssertTrue(first.waitForExistence(timeout: 10), "Finish opened no summary")
    XCTAssertTrue(first.label.hasPrefix("Dumbbell fly"), first.label)
  }
}
