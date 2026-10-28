import XCTest

/// S-043: Food follows the walkthrough. The camera keeps today's total on a scrim strip, the
/// shutter opens the match sheet with totals first and half-step servings, and History opens Food
/// Today with this week as one low-to-high band per day. "photo-match" is the synthetic fixture.
final class FoodUITests: XCTestCase {
  @MainActor
  private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 10) {
    expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: element)
    waitForExpectations(timeout: timeout)
  }

  @MainActor
  func testMatchSheetServingsAndFoodToday() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "photo-match")

    // Camera, as the walkthrough draws it: Home on its disc and Photo/Barcode at the top, the
    // today strip on the scrim under them, then Search; History beside the shutter at the bottom.
    let card = app.element("home.card.food")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no food card on Home")
    card.tap()
    let strip = app.element("food.strip.kcal")
    XCTAssertTrue(strip.waitForExistence(timeout: 10), "no today strip")
    waitForLabel(strip, "-- kcal")
    for id in ["nav.home", "food.search.field", "food.history", "food.mode.photo", "food.shutter"] {
      XCTAssertTrue(app.element(id).waitForExistence(timeout: 10), "no \(id) on the camera")
    }
    let shutter = app.element("food.shutter")
    XCTAssertLessThan(strip.frame.maxY, shutter.frame.minY, "the strip is not above the shutter")
    XCTAssertLessThan(
      strip.frame.maxY, app.element("food.search.field").frame.minY, "Search is not under it")
    let history = app.element("food.history").frame
    XCTAssertLessThan(history.maxX, shutter.frame.minX, "History is not beside the shutter")
    XCTAssertGreaterThan(history.minY, strip.frame.maxY, "History is not at the bottom")
    expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: shutter)
    waitForExpectations(timeout: 10)
    saveScreenshot("s043-camera", of: app)

    // Match sheet: totals first, then the items; + raises Roast Vegetables to 1.5 servings and
    // the item and the totals follow.
    shutter.tap()
    let title = app.element("food.match.title")
    XCTAssertTrue(title.waitForExistence(timeout: 15), "no match sheet")
    let kcal = app.element("food.match.total.kcal")
    let protein = app.element("food.match.total.protein")
    XCTAssertEqual(kcal.label, "460-780 kcal")
    XCTAssertEqual(protein.label, "7-13 g protein")
    XCTAssertLessThan(
      kcal.frame.maxY, app.element("food.match.item.0.name").frame.minY, "totals are not first")
    XCTAssertEqual(app.element("food.match.item.1.servings").label, "1 x 1/2 cup")
    app.element("food.match.item.1.plus").tap()
    XCTAssertEqual(app.element("food.match.item.1.servings").label, "1.5 x 1/2 cup")
    XCTAssertEqual(app.element("food.match.item.1.kcal").label, "120-180 kcal")
    XCTAssertEqual(kcal.label, "500-840 kcal", "the energy total did not follow")
    XCTAssertEqual(protein.label, "8-15 g protein", "the protein total did not follow")
    XCTAssertTrue(app.element("food.edit.add").exists, "no Add item")
    let log = app.element("food.edit.log")
    XCTAssertTrue(log.exists, "no Log")
    XCTAssertGreaterThan(log.frame.width, app.windows.firstMatch.frame.width * 0.8, "Log is narrow")
    saveScreenshot("s043-match-sheet", of: app)

    // Log closes the sheet to the camera; the strip follows.
    log.tap()
    expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: title)
    waitForExpectations(timeout: 10)
    waitForLabel(strip, "500-840 kcal")

    // Food Today: the ranges large, the meal, and this week with a band for today, "so far".
    app.element("food.history").tap()
    XCTAssertTrue(app.element("food.history.title").waitForExistence(timeout: 10), "no Food Today")
    let today = "food.history.day.0"
    waitForLabel(app.element("\(today).kcal"), "500-840 kcal")
    XCTAssertEqual(app.element("\(today).protein").label, "8-15 g protein")
    XCTAssertEqual(
      app.element("\(today).meal.0.items").label, "Herb Rice, Roast Vegetables, Brownie")
    XCTAssertEqual(app.element("\(today).meal.0.ranges").label, "500-840 kcal, 8-15 g protein")
    let band = app.element("food.today.week.6")
    XCTAssertTrue(band.waitForExistence(timeout: 5), "no band for today")
    XCTAssertTrue(band.label.hasSuffix("500-840 kcal, so far"), "today's band: \(band.label)")
    XCTAssertTrue(app.element("food.today.week.5").label.hasSuffix("--"), "a missing day is not --")
    for word in ["remaining", "target", "goal"] {
      let found = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", word))
      XCTAssertEqual(found.count, 0, "Food Today shows \"\(word)\"")
    }
    saveScreenshot("s043-food-today", of: app)
  }
}
