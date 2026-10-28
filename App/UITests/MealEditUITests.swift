import XCTest

/// S-015: after a photo (the synthetic fixture match), fix the item list: replace an item by
/// tapping its name, step servings in halves (never below 0.5), swipe one away, add one from search,
/// then the single Log tap saves the meal, closes the sheet to the camera and shows an undo toast.
final class MealEditUITests: XCTestCase {
  @MainActor
  func testFixItemsAndLog() {
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
    XCTAssertEqual(app.element("food.match.item.1.name").label, "Roast Vegetables")
    XCTAssertEqual(app.element("food.match.total.kcal").label, "460–780 kcal")

    // Step 1: tap an item's name, search, pick a replacement. The item and the totals update.
    app.element("food.match.item.1.name").tap()
    search(app, pick: "food.search.result.open_food_facts.0.name")
    XCTAssertTrue(title.waitForExistence(timeout: 10), "the list did not come back")
    XCTAssertEqual(app.element("food.match.item.1.name").label, "Plain Yogurt")
    XCTAssertEqual(app.element("food.match.item.1.servings").label, "1 x 1 cup")
    XCTAssertEqual(app.element("food.match.item.1.kcal").label, "75–125 kcal")
    XCTAssertEqual(app.element("food.match.item.1.protein").label, "12–20 g protein")
    XCTAssertEqual(app.element("food.match.total.kcal").label, "455–785 kcal")
    XCTAssertEqual(app.element("food.match.total.protein").label, "17–30 g protein")

    // Step 2: + and - step servings by halves, never below 0.5; the ranges recompute.
    app.element("food.match.item.0.plus").tap()
    XCTAssertEqual(app.element("food.match.item.0.servings").label, "2 x 4 oz")
    XCTAssertEqual(app.element("food.match.item.0.kcal").label, "307–413 kcal")
    XCTAssertEqual(app.element("food.match.item.0.protein").label, "5–8 g protein")
    app.element("food.match.item.2.minus").tap()
    app.element("food.match.item.2.minus").tap()
    XCTAssertEqual(app.element("food.match.item.2.servings").label, "0.5 x serving")
    XCTAssertEqual(app.element("food.match.item.2.kcal").label, "75–175 kcal")
    XCTAssertEqual(app.element("food.match.total.kcal").label, "457–713 kcal")

    // Step 3: remove an item with a swipe left (S-050); it leaves the list and the totals.
    app.element("food.match.item.2").swipeLeft()
    XCTAssertFalse(app.element("food.match.item.2.name").waitForExistence(timeout: 2))
    XCTAssertEqual(app.element("food.match.total.kcal").label, "382–538 kcal")
    XCTAssertEqual(app.element("food.match.total.protein").label, "17–28 g protein")

    // Step 4: + Add item, search and pick; it joins the list at 1 serving.
    app.element("food.edit.add").tap()
    search(app, pick: "food.search.result.dining.0.name")
    let added = app.element("food.match.item.2.name")
    XCTAssertTrue(added.waitForExistence(timeout: 10), "the pick did not join the list")
    XCTAssertEqual(added.label, "Herb Rice")
    XCTAssertEqual(app.element("food.match.item.2.servings").label, "1 x 4 oz")
    XCTAssertEqual(app.element("food.match.item.2.kcal").label, "120–200 kcal")
    XCTAssertEqual(app.element("food.match.total.kcal").label, "502–738 kcal")
    XCTAssertEqual(app.element("food.match.total.protein").label, "20–33 g protein")
    saveScreenshot("s015-edited", of: app)

    // Step 5: the single Log tap saves the meal, closes the sheet and shows an undo toast.
    app.element("food.edit.log").tap()
    expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: title)
    waitForExpectations(timeout: 10)
    XCTAssertTrue(app.element("food.logged.toast").waitForExistence(timeout: 5), "no toast")
    XCTAssertEqual(app.element("food.logged.toast").label, "Lunch logged, in Health")
    XCTAssertTrue(app.element("food.logged.undo").exists, "no Undo on the toast")
    XCTAssertTrue(app.element("food.shutter").exists, "not back on the camera")
    XCTAssertFalse(app.element("food.log.error").exists)
    saveScreenshot("s015-logged", of: app)
  }

  /// Types into the sheet's search bar, closes the keyboard and taps one result.
  @MainActor
  private func search(_ app: XCUIApplication, pick result: String) {
    let field = app.element("food.edit.search.field")
    XCTAssertTrue(field.waitForExistence(timeout: 5), "search did not open")
    field.tap()
    field.typeText("rice\n")
    let row = app.element(result)
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no result \(result)")
    row.tap()
  }
}
