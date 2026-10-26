import XCTest

/// S-018: logging a meal (the synthetic fixture match) saves it on the phone, then writes it to
/// Health through the fake HealthStore as one food entry. The toast then says "In Health".
final class MealHealthUITests: XCTestCase {
  @MainActor
  func testLoggedMealIsInHealth() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "photo-match")

    let card = app.element("home.card.food")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no food card on Home")
    card.tap()
    let shutter = app.element("food.shutter")
    XCTAssertTrue(shutter.waitForExistence(timeout: 10), "no shutter")
    expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: shutter)
    waitForExpectations(timeout: 10)
    shutter.tap()
    let title = app.element("food.match.title")
    XCTAssertTrue(title.waitForExistence(timeout: 15), "no match sheet")
    XCTAssertEqual(app.element("food.match.total.kcal").label, "460-780 kcal")

    // Step 1: the Log tap saves the meal and writes it to Health; no extra tap.
    app.element("food.edit.log").tap()
    expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: title)
    waitForExpectations(timeout: 10)
    let toast = app.element("food.logged.toast")
    XCTAssertTrue(toast.waitForExistence(timeout: 5), "no toast")
    XCTAssertEqual(toast.label, "Meal logged")
    XCTAssertFalse(app.element("food.log.error").exists, "the meal was not saved")

    // Step 2: the fake HealthStore took the write, so the meal shows In Health.
    let health = app.element("food.logged.health")
    XCTAssertTrue(health.waitForExistence(timeout: 5), "no Health state on the logged meal")
    XCTAssertEqual(health.label, "In Health")
    saveScreenshot("s018-in-health", of: app)
  }
}
