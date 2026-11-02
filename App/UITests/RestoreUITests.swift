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

  /// S-058: a fresh install ("restore-fresh": nothing on the phone; a fake VM holding two made-up
  /// visits this week, a fix, a weigh-in and the place "Gym") is offered a restore once Settings
  /// saves a server. One tap on Restore fills the Places map, the weight row and Gym's name on
  /// the newer visit, and nothing is queued back.
  @MainActor
  func testFreshInstallOffersRestore() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "restore-fresh")

    let gear = app.element("home.settings")
    XCTAssertTrue(gear.waitForExistence(timeout: 30), "no gear on Home")
    gear.tap()
    let address = app.textFields["settings.address"]
    XCTAssertTrue(address.waitForExistence(timeout: 10), "no Server address field")
    address.tap()
    address.typeText("https://vm.example")
    let token = app.secureTextFields["settings.token"]
    token.tap()
    token.typeText("synthetic-token\n")
    app.element("settings.save").tap()

    // The offer: what the VM holds, with Restore and Not now.
    let offer = app.element("settings.offer.text")
    XCTAssertTrue(offer.waitForExistence(timeout: 15), "no restore offer after Save")
    XCTAssertEqual(offer.label, "No program, 0 workouts (0 sets), 0 meals, 2 visits, 1 place")
    XCTAssertTrue(app.element("settings.offer.later").exists, "no Not now")
    saveScreenshot("s058-restore-offer", of: app)
    app.element("settings.offer.restore").tap()
    let status = app.element("settings.restore.status")
    wait(for: "label == 'Restored 0 workouts, 0 meals, 2 visits, 1 weigh-in, 1 place'", on: status)
    XCTAssertFalse(app.element("settings.offer.text").exists, "the offer is still open")
    XCTAssertFalse(
      app.element("settings.sync.status").label.contains("waiting"), "a restored record was queued")
    app.element("settings.done").tap()

    // Data: the weight row counts the restored weigh-in.
    let data = app.element("home.card.data")
    XCTAssertTrue(data.waitForExistence(timeout: 10), "Settings did not close")
    data.tap()
    let weight = app.element("data.weight.coverage")
    XCTAssertTrue(weight.waitForExistence(timeout: 10), "no Weight row")
    wait(for: "label == 'Weigh-ins 1 of 7'", on: weight)

    // Places: the map draws the restored log, and the newer visit takes his place's name.
    let row = app.element("data.places.open")
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no Places row")
    for _ in 0..<3 where !row.isHittable { app.swipeUp() }
    row.tap()
    XCTAssertTrue(app.element("places.map").waitForExistence(timeout: 10), "no map")
    let newest = app.element("places.visit.0.name")
    XCTAssertTrue(newest.waitForExistence(timeout: 10), "no restored visit")
    wait(for: "label == 'Gym'", on: newest)
    XCTAssertTrue(app.element("places.visit.1").exists, "the second visit is missing")
    saveScreenshot("s058-restored-places", of: app)
  }
}
