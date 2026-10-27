import XCTest

/// S-011 and S-034: on Workout, Import program checks a file whole. A valid file asks to replace
/// the program, naming its templates; Replace leaves exactly the file's templates in its order,
/// and History keeps sessions of removed templates under their names. An invalid file shows what
/// is wrong and changes nothing. The fixture picker returns a generic Push and Pull program.
final class ProgramImportUITests: XCTestCase {
  @MainActor
  private func openWorkout(_ app: XCUIApplication) {
    let card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card on Home")
    card.tap()
    let name = app.element("workout.today.name")
    XCTAssertTrue(name.waitForExistence(timeout: 10), "no next template card")
    XCTAssertEqual(name.label, "Day 1 Push", "the seed did not load")
  }

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

  /// The Replace confirmation, after checking it names the fixture's two templates.
  @MainActor
  private func confirmation(_ app: XCUIApplication) -> XCUIElement {
    let alert = app.alerts.firstMatch
    XCTAssertTrue(alert.waitForExistence(timeout: 10), "no Replace confirmation")
    XCTAssertTrue(
      alert.staticTexts["Replace your program with Push, Pull?"].exists, alert.debugDescription)
    XCTAssertTrue(alert.staticTexts["Your workout history is kept."].exists)
    XCTAssertTrue(alert.buttons["Replace"].exists, "no Replace")
    XCTAssertTrue(alert.buttons["Cancel"].exists, "no Cancel")
    return alert
  }

  @MainActor
  private func message(_ app: XCUIApplication) -> XCUIElement {
    let message = app.element("workout.import.message")
    XCTAssertTrue(message.waitForExistence(timeout: 10), "the import showed no result")
    return message
  }

  /// D-083 changed this test: the import now asks first, and it replaces the whole program, so
  /// the seed's other days are gone instead of kept.
  @MainActor
  func testImportProgramFromFile() {
    continueAfterFailure = false

    // Steps 1-2: Import, Replace; the file is now the program and the screen says how many.
    var app = UITestApp.launch()
    openWorkout(app)
    tap("workout.import", in: app)
    confirmation(app).buttons["Replace"].firstMatch.tap()
    XCTAssertEqual(message(app).label, "Imported 2 templates")
    XCTAssertTrue(app.element("workout.template.pull").exists, "Pull was not added")
    for key in ["day-2", "day-3", "day-4", "day-5"] {
      XCTAssertFalse(app.element("workout.template.\(key)").exists, "\(key) was kept")
    }
    XCTAssertTrue(app.element("workout.template.empty").exists, "Empty workout was lost")
    XCTAssertEqual(app.element("workout.today.name").label, "Push")
    app.swipeUp()
    saveScreenshot("s011-imported", of: app)

    // Step 3: an invalid file says what is wrong, asks nothing and leaves the templates.
    app.terminate()
    app = UITestApp.launch(scenario: "program-invalid")
    openWorkout(app)
    tap("workout.import", in: app)
    let refused = message(app)
    XCTAssertFalse(app.alerts.firstMatch.exists, "an invalid file asked to replace")
    XCTAssertTrue(refused.label.hasPrefix("Import failed."), refused.label)
    XCTAssertTrue(refused.label.contains("rep range"), refused.label)
    XCTAssertFalse(app.element("workout.template.pull").exists, "an invalid file added Pull")
    XCTAssertTrue(app.element("workout.template.day-2").exists, "an invalid file removed Day 2")
    XCTAssertEqual(app.element("workout.today.name").label, "Day 1 Push")
  }

  @MainActor
  func testImportReplacesProgramAndKeepsHistory() {
    continueAfterFailure = false
    let app = UITestApp.launch()
    openWorkout(app)

    // A finished session from Day 3 Legs, which the file lacks.
    tap("workout.template.day-3", in: app)
    let log = app.element("workout.logger.log")
    XCTAssertTrue(log.waitForExistence(timeout: 10), "the Log card did not open")
    XCTAssertEqual(app.element("workout.logger.exercise").label, "Back squat")
    log.tap()
    XCTAssertTrue(app.element("workout.logger.logged.0").waitForExistence(timeout: 5))
    app.element("workout.logger.finish").tap()
    let row = app.element("workout.session.0")
    XCTAssertTrue(row.waitForExistence(timeout: 10), "the finished session is not shown")
    XCTAssertTrue(row.label.hasPrefix("Day 3 Legs"), row.label)

    // Step 1: the confirmation names the file's templates; Cancel changes nothing.
    tap("workout.import", in: app)
    let alert = confirmation(app)
    saveScreenshot("s034-replace-confirm", of: app)
    alert.buttons["Cancel"].firstMatch.tap()
    let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: alert)
    wait(for: [closed], timeout: 10)
    // D-089: Next follows the Day 3 session just finished.
    XCTAssertEqual(app.element("workout.today.name").label, "Day 4 Upper", "Cancel changed it")
    XCTAssertTrue(app.element("workout.template.day-3").exists, "Cancel removed Day 3")
    XCTAssertFalse(app.element("workout.template.pull").exists, "Cancel added Pull")
    XCTAssertFalse(app.element("workout.import.message").exists, "Cancel imported")

    // Step 2: Replace leaves exactly Push then Pull (and Empty workout); the seed's days are gone.
    tap("workout.import", in: app)
    confirmation(app).buttons["Replace"].firstMatch.tap()
    XCTAssertEqual(message(app).label, "Imported 2 templates")
    XCTAssertEqual(app.element("workout.today.name").label, "Push", "Push is not first")
    XCTAssertTrue(app.element("workout.template.pull").exists, "Pull is not listed")
    XCTAssertTrue(app.element("workout.template.empty").exists, "Empty workout was lost")
    for key in ["day-1", "day-2", "day-3", "day-4", "day-5"] {
      XCTAssertFalse(app.element("workout.template.\(key)").exists, "\(key) was kept")
    }

    // Step 3: the finished Day 3 Legs session keeps its name this week and in History.
    XCTAssertTrue(row.exists, "the finished session was lost")
    XCTAssertTrue(row.label.hasPrefix("Day 3 Legs"), row.label)
    app.swipeDown()
    saveScreenshot("s034-program-replaced", of: app)
    tap("workout.history", in: app, up: false)
    let session = app.element("history.session.0.0")
    XCTAssertTrue(session.waitForExistence(timeout: 10), "no session in History")
    XCTAssertTrue(session.label.hasPrefix("Day 3 Legs"), session.label)
  }
}
