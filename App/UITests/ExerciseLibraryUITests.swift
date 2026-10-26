import XCTest

/// S-007: the exercise menu's Swap opens the Exercises library; a pick replaces the exercise for
/// this session only. New exercise adds a custom one that can be picked.
final class ExerciseLibraryUITests: XCTestCase {
  @MainActor
  func testSwapFromLibrary() {
    continueAfterFailure = false
    // Synthetic history: overhead press was last done 2 days ago; dumbbell fly never.
    let app = UITestApp.launch(scenario: "workout-history")
    openLibrary(app)

    // Step 1: a search field and rows grouped by muscle, each with when it was last done.
    XCTAssertTrue(app.element("workout.library.search").exists, "no search field")
    let overhead = app.element("workout.library.row.overhead-press")
    let fly = app.element("workout.library.row.dumbbell-fly")
    let bench = app.element("workout.library.row.bench-press")
    XCTAssertTrue(overhead.exists && fly.exists && bench.exists, "library rows missing")
    XCTAssertEqual(overhead.value as? String, "2d ago")
    XCTAssertEqual(fly.value as? String, "--")
    saveScreenshot("s007-library", of: app)

    // Step 2: part of a name filters the list, ignoring case; a tap swaps the exercise in.
    let search = app.element("workout.library.search")
    search.tap()
    search.typeText("DUMBBELL")
    XCTAssertTrue(bench.waitForNonExistence(timeout: 5), "the search did not filter")
    XCTAssertTrue(fly.exists, "the search hid a match")
    fly.tap()
    let exercise = app.element("workout.logger.exercise")
    XCTAssertTrue(exercise.waitForExistence(timeout: 10), "the logger did not come back")
    XCTAssertEqual(exercise.label, "Dumbbell fly")
    XCTAssertEqual(app.element("workout.logger.set").label, "Set 1 of 3")
    XCTAssertEqual(app.element("workout.logger.reps").label, "6-10 reps")
    XCTAssertEqual(app.element("workout.logger.weight").label, "--")
    saveScreenshot("s007-swapped", of: app)
  }

  @MainActor
  func testAddCustomExercise() {
    continueAfterFailure = false
    let app = UITestApp.launch()
    openLibrary(app)

    // Step 3: New exercise, the four fields, Save.
    app.element("workout.library.new").tap()
    type("Cable fly", into: "workout.library.custom.name", app)
    type("Cable", into: "workout.library.custom.equipment", app)
    type("Chest", into: "workout.library.custom.muscle", app)
    type("75", into: "workout.library.custom.rest", app)
    app.element("workout.library.custom.save").tap()

    let row = app.element("workout.library.row.custom-cable-fly")
    XCTAssertTrue(row.waitForExistence(timeout: 5), "the custom exercise is not listed")
    XCTAssertTrue(row.label.contains("custom"), row.label)
    XCTAssertEqual(row.value as? String, "--")
    saveScreenshot("s007-custom", of: app)

    row.tap()
    let exercise = app.element("workout.logger.exercise")
    XCTAssertTrue(exercise.waitForExistence(timeout: 10), "the logger did not come back")
    XCTAssertEqual(exercise.label, "Cable fly")
  }

  /// Home, Workout, Start, then the exercise menu and Swap.
  @MainActor
  private func openLibrary(_ app: XCUIApplication) {
    let card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card on Home")
    card.tap()
    let start = app.element("workout.today.start")
    XCTAssertTrue(start.waitForExistence(timeout: 10), "no Start on the Workout screen")
    start.tap()
    let menu = app.element("workout.logger.menu")
    XCTAssertTrue(menu.waitForExistence(timeout: 10), "no exercise menu on the Log card")
    XCTAssertEqual(app.element("workout.logger.exercise").label, "Bench press")
    menu.tap()
    let swap = app.element("workout.logger.swap")
    if swap.waitForExistence(timeout: 3) {
      swap.tap()
    } else {
      app.buttons["Swap"].tap()
    }
    XCTAssertTrue(
      app.element("workout.library.title").waitForExistence(timeout: 10),
      "the Exercises library did not open")
  }

  @MainActor
  private func type(_ text: String, into id: String, _ app: XCUIApplication) {
    let field = app.element(id)
    XCTAssertTrue(field.waitForExistence(timeout: 5), "no field \(id)")
    field.tap()
    field.typeText(text)
  }
}
