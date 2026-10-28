import XCTest

/// S-019: the camera's strip shows today's food as summed ranges with no target, and History
/// lists past days with their meals; a meal is edited (its Health entry replaced) and deleted.
/// The "food-history" meals are made up (D-034).
final class MealHistoryUITests: XCTestCase {
  @MainActor
  private func openFood(_ app: XCUIApplication) {
    let card = app.element("home.card.food")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no food card on Home")
    card.tap()
  }

  @MainActor
  private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 10) {
    expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: element)
    waitForExpectations(timeout: timeout)
  }

  @MainActor
  func testTodayTotalsAndEditDeleteMeal() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "food-history")
    openFood(app)

    // Step 1: today's totals with 0 taps, as summed ranges; no target, ring or remaining.
    let kcal = app.element("food.strip.kcal")
    XCTAssertTrue(kcal.waitForExistence(timeout: 10), "no today strip on the camera")
    waitForLabel(kcal, "330–450 kcal")
    XCTAssertEqual(app.element("food.strip.protein").label, "20–27 g protein")
    XCTAssertEqual(app.element("food.strip.meals").label, "2 meals")
    for word in ["remaining", "target", "goal"] {
      let found = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", word))
      XCTAssertEqual(found.count, 0, "the camera shows \"\(word)\"")
    }
    saveScreenshot("s019-today", of: app)

    // Step 2: History lists days newest first with their totals; the pending photo is pinned at
    // the top of its day; each meal has a thumbnail, its items, ranges and source.
    app.element("food.history").tap()
    XCTAssertTrue(app.element("food.history.title").waitForExistence(timeout: 10), "no History")
    let today = "food.history.day.0"
    let lunch = "\(today).meal.0"
    XCTAssertTrue(app.element("\(lunch).items").waitForExistence(timeout: 10), "no meal today")
    XCTAssertEqual(app.element("\(today).kcal").label, "330–450 kcal")
    XCTAssertEqual(app.element("\(today).protein").label, "20–27 g protein")
    XCTAssertEqual(app.element("\(lunch).items").label, "Herb Rice, Roast Vegetables")
    XCTAssertEqual(app.element("\(lunch).ranges").label, "240–340 kcal, 6–9 g protein")
    XCTAssertTrue(app.element("\(lunch).source").label.contains("North Hall, South Hall"))
    XCTAssertEqual(app.element("\(lunch).photo").label, "Photo", "no thumbnail")
    XCTAssertEqual(app.element("\(today).meal.1.items").label, "Plain Yogurt")
    let yesterday = "food.history.day.1"
    XCTAssertEqual(app.element("\(yesterday).kcal").label, "360–440 kcal")
    let pending = app.element("\(yesterday).pending.0.items")
    let burrito = app.element("\(yesterday).meal.0.items")
    XCTAssertTrue(pending.exists, "no pending photo")
    XCTAssertEqual(burrito.label, "Bean Burrito")
    XCTAssertLessThan(pending.frame.minY, burrito.frame.minY, "pending is not pinned at the top")
    saveScreenshot("s019-history", of: app)

    // Step 3: a tap opens the same item editor; half a serving more of Herb Rice, then Save.
    app.element("\(lunch).items").tap()
    let editor = app.element("food.match.title")
    XCTAssertTrue(editor.waitForExistence(timeout: 10), "no item editor")
    app.element("food.match.item.0.plus").tap()
    XCTAssertEqual(app.element("food.match.total.kcal").label, "320–450 kcal")
    app.element("food.edit.save").tap()
    expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: editor)
    waitForExpectations(timeout: 10)
    waitForLabel(app.element("\(lunch).ranges"), "320–450 kcal, 8–12 g protein")
    XCTAssertEqual(app.element("\(today).kcal").label, "410–560 kcal")
    XCTAssertEqual(app.element("\(today).protein").label, "22–30 g protein")
    XCTAssertTrue(
      app.element("\(lunch).source").label.hasSuffix("In Health"), "the edit is not in Health")
    saveScreenshot("s019-edited", of: app)

    // Step 4: Delete takes the meal out of the list and the totals.
    app.element("\(lunch).delete").tap()
    waitForLabel(app.element("\(today).kcal"), "90–110 kcal")
    XCTAssertEqual(app.element("\(today).protein").label, "14–18 g protein")
    XCTAssertEqual(app.element("\(lunch).items").label, "Plain Yogurt")
    XCTAssertFalse(app.element("\(today).meal.1.items").exists, "the deleted meal is listed")
    app.element("food.history.done").tap()
    waitForLabel(app.element("food.strip.kcal"), "90–110 kcal")
    XCTAssertEqual(app.element("food.strip.meals").label, "1 meal")

    // Nothing logged shows "--", never 0.
    app.terminate()
    let empty = UITestApp.launch()
    openFood(empty)
    let none = empty.element("food.strip.kcal")
    XCTAssertTrue(none.waitForExistence(timeout: 10), "no today strip")
    waitForLabel(none, "-- kcal")
    XCTAssertEqual(empty.element("food.strip.protein").label, "-- g protein")
    XCTAssertEqual(empty.element("food.strip.meals").label, "-- meals")
  }
}
