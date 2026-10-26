import XCTest

/// S-014: on the camera screen, type into the search bar; GET /search (the fake answers with a
/// synthetic fixture) lists dining hall items with their halls, restaurant dishes and packaged
/// food. A tap opens the item list at 1 serving; "Estimate from text" gives a rough item.
final class FoodSearchUITests: XCTestCase {
  @MainActor
  func testSearchPicksItemAndTextFallback() {
    continueAfterFailure = false
    let app = UITestApp.launch()

    let card = app.element("home.card.food")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no food card on Home")
    card.tap()

    // Step 1: one tap into the search bar, then typing. Results come grouped.
    let field = app.element("food.search.field")
    XCTAssertTrue(field.waitForExistence(timeout: 10), "no search bar on the camera screen")
    field.tap()
    field.typeText("rice")

    let dining = app.element("food.search.result.dining.0.name")
    XCTAssertTrue(dining.waitForExistence(timeout: 10), "no dining results")
    XCTAssertTrue(app.element("food.search.group.dining").exists)
    XCTAssertTrue(app.element("food.search.group.usda_fdc").exists, "no restaurant group")
    XCTAssertTrue(app.element("food.search.group.open_food_facts").exists, "no packaged group")
    XCTAssertEqual(dining.label, "Herb Rice")
    XCTAssertEqual(
      app.element("food.search.result.dining.0.detail").label, "North Hall, South Hall · 4 oz")
    XCTAssertEqual(app.element("food.search.result.dining.0.kcal").label, "120-200 kcal")
    XCTAssertEqual(
      app.element("food.search.result.usda_fdc.0.name").label, "Bean burrito, restaurant")
    XCTAssertEqual(app.element("food.search.result.open_food_facts.0.name").label, "Plain Yogurt")
    XCTAssertEqual(
      app.element("food.search.result.open_food_facts.0.detail").label, "Example Dairy · 1 cup")
    saveScreenshot("s014-results", of: app)

    // Step 2: one tap picks; the item list opens with it at 1 serving and its ranges.
    dining.tap()
    let title = app.element("food.match.title")
    XCTAssertTrue(title.waitForExistence(timeout: 10), "no item list after the pick")
    XCTAssertEqual(app.element("food.match.item.0.name").label, "Herb Rice")
    XCTAssertEqual(app.element("food.match.item.0.hall").label, "North Hall")
    XCTAssertEqual(app.element("food.match.item.0.servings").label, "1 x 4 oz")
    XCTAssertEqual(app.element("food.match.item.0.kcal").label, "120-200 kcal")
    XCTAssertEqual(app.element("food.match.item.0.protein").label, "3-5 g protein")
    XCTAssertFalse(app.element("food.match.item.0.rough").exists)
    XCTAssertEqual(app.element("food.match.total.kcal").label, "120-200 kcal")

    title.swipeDown(velocity: .fast)
    if title.waitForExistence(timeout: 2) {
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
    }
    expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: title)
    waitForExpectations(timeout: 10)

    // Step 3: no good match, so "Estimate from text": rough badge, wider range.
    let estimate = app.element("food.search.estimate")
    XCTAssertTrue(estimate.waitForExistence(timeout: 5), "no Estimate from text")
    estimate.tap()
    XCTAssertTrue(title.waitForExistence(timeout: 10), "no item list for the estimate")
    XCTAssertEqual(app.element("food.match.item.0.name").label, "Noodle Bowl")
    XCTAssertTrue(app.element("food.match.item.0.rough").exists, "the estimate is not rough")
    XCTAssertEqual(app.element("food.match.item.0.servings").label, "1 x 1 bowl")
    XCTAssertEqual(app.element("food.match.item.0.kcal").label, "420-980 kcal")
    XCTAssertEqual(app.element("food.match.item.0.protein").label, "12-28 g protein")
    saveScreenshot("s014-text-estimate", of: app)
  }
}
