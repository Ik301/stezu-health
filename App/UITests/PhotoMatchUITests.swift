import XCTest

/// S-013: one tap on the shutter sends the photo to POST /scan (the fake answers with a synthetic
/// fixture) and a sheet lists the matched items with ranges, halls, servings and totals.
final class PhotoMatchUITests: XCTestCase {
  @MainActor
  func testPhotoShowsMatchedItemsWithRanges() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "photo-match")

    let card = app.element("home.card.food")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no food card on Home")
    card.tap()
    let shutter = app.element("food.shutter")
    XCTAssertTrue(shutter.waitForExistence(timeout: 10), "no shutter")
    expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: shutter)
    waitForExpectations(timeout: 10)

    // Step 1: one tap on the shutter sends the scan.
    shutter.tap()

    // Step 2: the matched items, each with hall, servings and kcal and protein ranges.
    XCTAssertTrue(app.element("food.match.title").waitForExistence(timeout: 15), "no match sheet")
    let expected: [(name: String, hall: String, servings: String, kcal: String, protein: String)] =
      [
        ("Herb Rice", "North Hall", "1.5 x 4 oz", "230–310 kcal", "4–6 g protein"),
        ("Roast Vegetables", "South Hall", "1 x 1/2 cup", "80–120 kcal", "2–3 g protein"),
        ("Brownie", "Not on a menu", "1 x serving", "150–350 kcal", "1–4 g protein"),
      ]
    for (index, item) in expected.enumerated() {
      let id = "food.match.item.\(index)"
      XCTAssertTrue(app.element("\(id).name").waitForExistence(timeout: 5), "no row \(index)")
      XCTAssertEqual(app.element("\(id).name").label, item.name)
      XCTAssertEqual(app.element("\(id).hall").label, item.hall)
      XCTAssertEqual(app.element("\(id).servings").label, item.servings)
      XCTAssertEqual(app.element("\(id).kcal").label, item.kcal)
      XCTAssertEqual(app.element("\(id).protein").label, item.protein)
    }
    XCTAssertEqual(app.element("food.match.total.kcal").label, "460–780 kcal")
    XCTAssertEqual(app.element("food.match.total.protein").label, "7–13 g protein")

    // Step 3: only the item on no menu carries the rough badge.
    XCTAssertTrue(app.element("food.match.item.2.rough").exists, "the unlisted item is not rough")
    XCTAssertFalse(app.element("food.match.item.0.rough").exists)
    XCTAssertFalse(app.element("food.match.item.1.rough").exists)
    saveScreenshot("s013-matched", of: app)
  }
}
