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

  /// S-052: a tap on the Places preview opens the map full screen on the newest made-up visit
  /// ("Dining hall"); it zooms, a tap on that visit opens its spot card as a sheet, and Done
  /// closes the full-screen map.
  @MainActor
  func testFullScreenMapZoomAndSpot() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "location")

    let card = app.element("home.card.data")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Data card on Home")
    card.tap()
    let row = app.element("data.places.open")
    XCTAssertTrue(row.waitForExistence(timeout: 10), "the Places row is not a button")
    for _ in 0..<3 where !row.isHittable { app.swipeUp() }
    row.tap()
    let preview = app.element("places.map")
    XCTAssertTrue(preview.waitForExistence(timeout: 10), "no map preview")
    XCTAssertTrue(app.element("places.map.expand").exists, "no Expand button")
    let named = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label == 'Dining hall'"),
      object: app.element("places.visit.0.name"))
    XCTAssertEqual(XCTWaiter().wait(for: [named], timeout: 15), .completed, "names not loaded")
    preview.tap()

    let map = app.element("places.map.full")
    XCTAssertTrue(map.waitForExistence(timeout: 10), "the map did not open full screen")
    XCTAssertTrue(app.element("places.map.done").exists, "no Done")
    XCTAssertEqual(app.element("places.map.title").label, "Places")
    map.pinch(withScale: 1.5, velocity: 1)
    map.tap()
    let name = app.element("places.spot.name")
    XCTAssertTrue(name.waitForExistence(timeout: 10), "tapping the visit opened no spot")
    XCTAssertEqual(name.label, "Dining hall")
    saveScreenshot("s052-places-full-map", of: app)

    app.element("places.map.done").tap()
    let closed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: map)
    XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 10), .completed, "Done did not close")
    XCTAssertTrue(app.element("places.title").exists, "Places is not back")
  }
}
