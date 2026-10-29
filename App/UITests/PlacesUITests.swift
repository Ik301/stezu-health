import XCTest

/// Data's Places row opens where Isaac has been this week: the "location" scenario's two
/// made-up visits, newest first, named by the fake geocoder. Done closes it.
final class PlacesUITests: XCTestCase {
  @MainActor
  func testPlacesRowOpensTheWeeksVisits() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "location")

    let card = app.element("home.card.data")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Data card on Home")
    card.tap()
    let row = app.element("data.places.open")
    XCTAssertTrue(row.waitForExistence(timeout: 10), "the Places row is not a button")
    for _ in 0..<3 where !row.isHittable { app.swipeUp() }
    row.tap()

    XCTAssertTrue(app.element("places.title").waitForExistence(timeout: 10), "Places did not open")
    let newest = app.element("places.visit.0.name")
    XCTAssertTrue(newest.waitForExistence(timeout: 10), "no visit listed")
    let named = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label == 'Dining hall'"), object: newest)
    XCTAssertEqual(XCTWaiter().wait(for: [named], timeout: 15), .completed, newest.label)
    XCTAssertEqual(app.element("places.visit.1.name").label, "Library")
    XCTAssertFalse(app.element("places.visit.2").exists, "a departure was listed twice")
    saveScreenshot("places-week", of: app)

    app.element("places.done").tap()
    let closed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: app.element("places.title"))
    XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 10), .completed, "Done did not close")
  }
}
