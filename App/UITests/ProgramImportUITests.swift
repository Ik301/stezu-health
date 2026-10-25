import XCTest

/// S-011: on Workout, Import program takes a file and upserts its templates by key; an invalid
/// file shows what is wrong and changes nothing. The fixture picker returns a generic program.
final class ProgramImportUITests: XCTestCase {
  @MainActor
  private func openWorkoutAndImport(_ app: XCUIApplication) -> XCUIElement {
    let card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card on Home")
    card.tap()
    let name = app.element("workout.today.name")
    XCTAssertTrue(name.waitForExistence(timeout: 10), "no next template card")
    XCTAssertEqual(name.label, "Day 1 Push", "the seed did not load")
    let button = app.element("workout.import")
    XCTAssertTrue(button.waitForExistence(timeout: 10), "no Import program button")
    if !button.isHittable { app.swipeUp() }
    button.tap()
    let message = app.element("workout.import.message")
    XCTAssertTrue(message.waitForExistence(timeout: 10), "the import showed no result")
    return message
  }

  @MainActor
  func testImportProgramFromFile() {
    continueAfterFailure = false

    // Steps 1-2: two taps; the file replaces Day 1 by key, adds Day 6 and says how many.
    var app = UITestApp.launch()
    var message = openWorkoutAndImport(app)
    XCTAssertEqual(message.label, "Imported 2 templates")
    XCTAssertTrue(app.element("workout.template.day-6").exists, "Day 6 was not added")
    for key in ["day-2", "day-3", "day-4", "day-5", "empty"] {
      XCTAssertTrue(app.element("workout.template.\(key)").exists, "\(key) was lost")
    }
    XCTAssertEqual(app.element("workout.today.name").label, "Day 1 Full body")
    app.swipeUp()
    saveScreenshot("s011-imported", of: app)

    // Step 3: an invalid file says what is wrong and leaves the templates as they were.
    app.terminate()
    app = UITestApp.launch(scenario: "program-invalid")
    message = openWorkoutAndImport(app)
    XCTAssertTrue(message.label.hasPrefix("Import failed."), message.label)
    XCTAssertTrue(message.label.contains("rep range"), message.label)
    XCTAssertFalse(app.element("workout.template.day-6").exists, "an invalid file added Day 6")
    XCTAssertEqual(app.element("workout.today.name").label, "Day 1 Push")
  }
}
