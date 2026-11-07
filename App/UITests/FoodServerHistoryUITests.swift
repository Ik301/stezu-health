import XCTest

/// S-063: an empty install whose fake VM holds one made-up meal from yesterday and one from
/// earlier today (D-034). Opening Food reads them: the strip counts today's, and History lists
/// both with "No photo". A meal then logged by search is listed first in today at once (D-156).
final class FoodServerHistoryUITests: XCTestCase {
  @MainActor
  private func wait(for label: String, on element: XCUIElement, timeout: TimeInterval = 15) {
    let done = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label == %@", label), object: element)
    XCTAssertEqual(
      XCTWaiter().wait(for: [done], timeout: timeout), .completed,
      "\(element) is \"\(element.exists ? element.label : "missing")\", wanted \(label)")
  }

  @MainActor
  func testServerMealsShowInHistoryThenSearchLogJoins() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "food-server-history")
    let card = app.element("home.card.food")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no food card on Home")
    card.tap()

    // Food reads the VM: the strip counts today's server meal.
    let meals = app.element("food.strip.meals")
    XCTAssertTrue(meals.waitForExistence(timeout: 10), "no today strip")
    wait(for: "1 meal", on: meals)
    XCTAssertEqual(app.element("food.strip.kcal").label, "90–210 kcal")

    // History: today's text estimate and yesterday's hall dish, each with "No photo".
    app.element("food.history").tap()
    let today = app.element("food.history.day.0.meal.0.items")
    XCTAssertTrue(today.waitForExistence(timeout: 10), "no server meal today")
    XCTAssertEqual(today.label, "Green Salad")
    XCTAssertEqual(app.element("food.history.day.0.meal.0.photo").label, "No photo")
    XCTAssertEqual(
      app.element("food.history.day.0.meal.0.ranges").label, "90–210 kcal, 2–6 g protein")
    XCTAssertTrue(app.element("food.history.day.0.meal.0.source").label.contains("Estimate"))
    let yesterday = app.element("food.history.day.1.meal.0.items")
    XCTAssertTrue(yesterday.waitForExistence(timeout: 10), "no server meal yesterday")
    XCTAssertEqual(yesterday.label, "Lentil Soup")
    XCTAssertEqual(
      app.element("food.history.day.1.meal.0.ranges").label, "180–240 kcal, 9–13 g protein")
    XCTAssertEqual(app.element("food.history.day.1.meal.0.photo").label, "No photo")
    saveScreenshot("s063-server-history", of: app)
    app.element("food.history.done").tap()

    // Log a meal by search; History lists it first in today, above the server meal.
    let field = app.element("food.search.field")
    XCTAssertTrue(field.waitForExistence(timeout: 10), "History did not close")
    field.tap()
    field.typeText("rice")
    let dining = app.element("food.search.result.dining.0.name")
    XCTAssertTrue(dining.waitForExistence(timeout: 10), "no search results")
    dining.tap()
    let log = app.element("food.edit.log")
    XCTAssertTrue(log.waitForExistence(timeout: 10), "no Log")
    log.tap()
    XCTAssertTrue(app.element("food.logged.toast").waitForExistence(timeout: 10), "no toast")
    wait(for: "2 meals", on: meals)
    app.element("food.history").tap()
    let first = app.element("food.history.day.0.meal.0.items")
    XCTAssertTrue(first.waitForExistence(timeout: 10), "no meal today")
    wait(for: "Herb Rice", on: first)
    XCTAssertEqual(app.element("food.history.day.0.meal.1.items").label, "Green Salad")
    XCTAssertEqual(app.element("food.history.day.1.meal.0.items").label, "Lentil Soup")
    saveScreenshot("s063-search-logged", of: app)
  }
}
