import XCTest

/// S-016: on the camera, one tap switches the pill to Barcode. In `-uitest` a fixture source
/// returns a synthetic code; GET /barcode (the fake answers with a made-up product) opens the item
/// list with the product, its serving label and ranges, ready to Log. An unknown code shows
/// "Not found" and offers search instead.
final class BarcodeUITests: XCTestCase {
  @MainActor
  func testBarcodeFindsProduct() {
    continueAfterFailure = false
    var app = UITestApp.launch()
    openFood(app)

    // Step 1: one tap switches to Barcode; the frame waits for a code. The fixture code comes
    // 8 seconds later, so the screenshot must be taken before the item list opens.
    app.element("food.mode.barcode").tap()
    let status = app.element("food.barcode.status")
    XCTAssertTrue(status.waitForExistence(timeout: 2), "no barcode status")
    XCTAssertFalse(app.element("food.match.title").exists, "the list opened before the shot")
    saveScreenshot("s016-barcode-mode", of: app)
    XCTAssertEqual(app.element("food.mode.barcode").value as? String, "on")
    XCTAssertEqual(app.element("food.mode.photo").value as? String, "off")
    XCTAssertFalse(app.element("food.shutter").exists, "Barcode mode has no shutter")

    // Step 2: the code goes to GET /barcode; the item list opens with the product at 1 serving.
    let title = app.element("food.match.title")
    XCTAssertTrue(title.waitForExistence(timeout: 25), "no item list for the scanned code")
    XCTAssertEqual(app.element("food.match.item.0.name").label, "Oat Bar")
    XCTAssertEqual(app.element("food.match.item.0.hall").label, "Example Foods")
    XCTAssertEqual(app.element("food.match.item.0.servings").label, "1 x 1 bar (40 g)")
    XCTAssertEqual(app.element("food.match.item.0.kcal").label, "120-200 kcal")
    XCTAssertEqual(app.element("food.match.item.0.protein").label, "3-5 g protein")
    XCTAssertFalse(app.element("food.match.item.0.rough").exists)
    XCTAssertEqual(app.element("food.match.total.kcal").label, "120-200 kcal")
    XCTAssertTrue(app.element("food.edit.log").exists, "not ready to Log")
    saveScreenshot("s016-product", of: app)

    // Step 3: an unknown code shows "Not found" and offers search instead.
    app.terminate()
    app = UITestApp.launch(scenario: "barcode-unknown")
    openFood(app)
    app.element("food.mode.barcode").tap()
    let notFound = app.element("food.barcode.status")
    expectation(for: NSPredicate(format: "label == 'Not found'"), evaluatedWith: notFound)
    waitForExpectations(timeout: 25)
    XCTAssertFalse(app.element("food.match.title").exists, "an unknown code opened a list")
    let search = app.element("food.barcode.search")
    XCTAssertTrue(search.exists, "Not found offers no search")
    search.tap()
    XCTAssertEqual(app.element("food.mode.photo").value as? String, "on")
    let field = app.element("food.search.field")
    XCTAssertTrue(field.waitForExistence(timeout: 5), "no search bar")
    field.tap()
    field.typeText("yogurt")
    let result = app.element("food.search.result.open_food_facts.0.name")
    XCTAssertTrue(result.waitForExistence(timeout: 10), "search found nothing")
  }

  @MainActor
  private func openFood(_ app: XCUIApplication) {
    let card = app.element("home.card.food")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no food card on Home")
    card.tap()
    XCTAssertTrue(app.element("food.mode.barcode").waitForExistence(timeout: 10), "no mode pill")
  }
}
