import XCTest

/// S-057: Restore from Hermes in Settings reads the fake VM's records ("restore": a generic
/// program, one Push session whose session record lists one of its three sets, one meal) into
/// the phone's stores. Workout shows the program and Next after the session, History has every
/// set, Food Today lists the meal without a photo, and the corrected session is the one record
/// sent back. Every value is made up (D-034).
final class RestoreUITests: XCTestCase {
  @MainActor
  private func wait(for format: String, on element: XCUIElement, timeout: TimeInterval = 15) {
    let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
    XCTAssertEqual(
      XCTWaiter().wait(for: [done], timeout: timeout), .completed,
      "\(element) is \"\(element.exists ? element.label : "missing")\", wanted \(format)")
  }

  @MainActor
  func testRestoreProgramWorkoutsAndMeals() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "restore", persist: true, reset: true)

    // Settings: the row says what the VM holds.
    let gear = app.element("home.settings")
    XCTAssertTrue(gear.waitForExistence(timeout: 30), "no gear on Home")
    gear.tap()
    let status = app.element("settings.restore.status")
    XCTAssertTrue(status.waitForExistence(timeout: 10), "no Restore from Hermes row")
    wait(for: "label == 'Program, 1 workout (3 sets), 1 meal, 0 visits, 0 places'", on: status)

    // Restore, then Confirm: the line says what came back, and the one corrected session
    // record reaches the fake server (its record count goes to 1).
    app.element("settings.restore").tap()
    let confirm = app.alerts.firstMatch.buttons["Restore"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 10), "no confirmation")
    confirm.tap()
    wait(for: "label == 'Restored program, 1 workout, 1 meal'", on: status)
    wait(for: "label CONTAINS ', 1 record'", on: app.element("settings.sync.status"))
    XCTAssertFalse(app.element("settings.sync.status").label.contains("waiting"))
    saveScreenshot("s057-restore-settings", of: app)
    app.element("settings.done").tap()

    // Workout: the restored program, and Next follows the restored Push session.
    let workout = app.element("home.card.workout")
    XCTAssertTrue(workout.waitForExistence(timeout: 10), "Settings did not close")
    workout.tap()
    let next = app.element("workout.today.name")
    XCTAssertTrue(next.waitForExistence(timeout: 10), "no Next card")
    XCTAssertEqual(next.label, "Pull")
    XCTAssertTrue(app.element("workout.template.push").exists, "the program's Push is missing")

    // History: the session with all three sets, rebuilt from the set records.
    app.element("workout.history").tap()
    let session = app.element("history.session.0.0")
    XCTAssertTrue(session.waitForExistence(timeout: 10), "no restored session in History")
    XCTAssertTrue(session.label.contains("3 sets"), "session row is \(session.label)")
    session.tap()
    let first = app.element("history.set.0.0")
    XCTAssertTrue(first.waitForExistence(timeout: 10), "no set chips")
    XCTAssertEqual(first.label, "60 x 8")
    XCTAssertEqual(app.element("history.set.0.1").label, "65 x 8")
    XCTAssertEqual(app.element("history.set.1.0").label, "40 x 8")
    saveScreenshot("s057-restored-history", of: app)
    app.element("history.session.back").tap()
    app.element("workout.history.done").tap()

    // Food Today: the meal, with "No photo" in its thumbnail.
    let food = app.element("nav.circle.food")
    XCTAssertTrue(food.waitForExistence(timeout: 10), "no area nav")
    food.tap()
    let history = app.element("food.history")
    XCTAssertTrue(history.waitForExistence(timeout: 10), "no Food history button")
    history.tap()
    let meal = app.element("food.history.day.0.meal.0.items")
    XCTAssertTrue(meal.waitForExistence(timeout: 10), "no meal today")
    XCTAssertEqual(meal.label, "Oat Porridge")
    XCTAssertEqual(app.element("food.history.day.0.meal.0.photo").label, "No photo")
  }
}
