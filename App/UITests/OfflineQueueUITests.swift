import XCTest

/// S-017: a photo taken offline is saved and waits as pending; today shows "+1 pending", never
/// 0 kcal. After a relaunch with the server back, opening Food retries the queue and the meal
/// comes back matched with its items and ranges, with no extra tap.
final class OfflineQueueUITests: XCTestCase {
  @MainActor
  func testOfflineMealQueuesAndMatchesLater() {
    continueAfterFailure = false

    // Step 1: offline, with a store that survives the relaunch, emptied first.
    var app = UITestApp.launch(offline: true, persist: true, reset: true)
    openFood(app).tap()
    XCTAssertTrue(
      app.element("food.match.pending").waitForExistence(timeout: 15), "the meal is not pending")
    XCTAssertEqual(app.element("food.match.pending").label, "Pending, will match when online")
    XCTAssertEqual(app.element("food.captured.saved").label, "Photo saved on this phone.")
    let today = app.element("food.today")
    XCTAssertTrue(today.waitForExistence(timeout: 5), "no today line")
    XCTAssertEqual(today.label, "Today: -- kcal, +1 pending")
    XCTAssertFalse(today.label.contains("0 kcal"))
    saveScreenshot("s017-pending", of: app)

    // Step 2: relaunch online with the same store. The scan answers with the synthetic fixture.
    app = UITestApp.launch(scenario: "photo-match", persist: true)
    _ = openFood(app)
    XCTAssertTrue(
      app.element("food.match.title").waitForExistence(timeout: 20), "the queued meal never matched"
    )
    XCTAssertEqual(app.element("food.match.item.0.name").label, "Herb Rice")
    XCTAssertEqual(app.element("food.match.item.0.kcal").label, "230–310 kcal")
    XCTAssertEqual(app.element("food.match.item.2.name").label, "Brownie")
    XCTAssertEqual(app.element("food.match.total.kcal").label, "460–780 kcal")
    XCTAssertEqual(app.element("food.match.total.protein").label, "7–13 g protein")
    XCTAssertFalse(app.element("food.match.pending").exists)
    saveScreenshot("s017-matched-later", of: app)
  }

  /// Opens Food from Home and returns the shutter once the camera allows it.
  @MainActor
  private func openFood(_ app: XCUIApplication) -> XCUIElement {
    let card = app.element("home.card.food")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no food card on Home")
    card.tap()
    let shutter = app.element("food.shutter")
    XCTAssertTrue(shutter.waitForExistence(timeout: 10), "no shutter")
    expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: shutter)
    waitForExpectations(timeout: 10)
    return shutter
  }
}
