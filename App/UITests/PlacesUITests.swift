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

  /// S-053: Monday's two made-up visits are 44 m apart (Library, then Dining hall). A long press
  /// on the full map starts a place, the radius slider covers both, it is named "Gym" and saved:
  /// both visits read "Gym" on the spot card, in Places and on the Day timeline. Deleting it
  /// brings the looked-up names back everywhere.
  @MainActor
  func testDrawPlaceLabelsEveryVisitInside() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "data-food-week")
    let card = app.element("home.card.data")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Data card on Home")
    card.tap()

    var map = openFullMap(app)
    map.press(forDuration: 1.5)
    let radius = app.sliders["places.new.radius"]
    XCTAssertTrue(radius.waitForExistence(timeout: 10), "a long press started no place")
    radius.adjust(toNormalizedSliderPosition: 0.5)
    wait(app.element("places.new.count"), "label == '2 visits inside'")
    let name = app.element("places.new.name")
    name.tap()
    name.typeText("Gym")
    let note = app.element("places.new.note")
    note.tap()
    note.typeText("Lift on Mon and Thu")
    saveScreenshot("s053-new-place", of: app)
    app.element("places.new.save").tap()
    wait(radius, "exists == false")

    map.tap()
    let spot = app.element("places.spot.name")
    wait(spot, "label == 'Gym'")
    XCTAssertEqual(app.element("places.spot.note").label, "Lift on Mon and Thu")
    saveScreenshot("s053-place-applied", of: app)
    app.element("places.map.done").tap()
    wait(app.element("places.visit.0.name"), "label == 'Gym'")
    XCTAssertEqual(app.element("places.visit.1.name").label, "Gym")
    app.element("places.done").tap()
    checkMonday(app, ["Gym, 08:00–11:50", "Gym, 12:10–17:50"])

    map = openFullMap(app)
    map.tap()
    wait(spot, "label == 'Gym'")
    app.element("places.spot.place").tap()
    let delete = app.element("places.new.delete")
    XCTAssertTrue(delete.waitForExistence(timeout: 10), "Edit place opened no editor")
    delete.tap()
    wait(radius, "exists == false")
    map.tap()
    wait(spot, "label == 'Dining hall' OR label == 'Library'")
    app.element("places.map.done").tap()
    wait(app.element("places.visit.0.name"), "label == 'Dining hall'")
    XCTAssertEqual(app.element("places.visit.1.name").label, "Library")
    app.element("places.done").tap()
    checkMonday(app, ["Library, 08:00–11:50", "Dining hall, 12:10–17:50"])
  }

  /// From Data: Places, then its map full screen.
  @MainActor
  private func openFullMap(_ app: XCUIApplication) -> XCUIElement {
    let row = app.element("data.places.open")
    XCTAssertTrue(row.waitForExistence(timeout: 10), "the Places row is not a button")
    for _ in 0..<3 where !row.isHittable { app.swipeUp() }
    row.tap()
    let preview = app.element("places.map")
    XCTAssertTrue(preview.waitForExistence(timeout: 10), "no map preview")
    XCTAssertTrue(app.element("places.visit.1.name").waitForExistence(timeout: 10), "no visits")
    preview.tap()
    let map = app.element("places.map.full")
    XCTAssertTrue(map.waitForExistence(timeout: 10), "the map did not open full screen")
    return map
  }

  /// From Data: Weight, this week, Monday; checks the timeline's visits, then back to Data.
  @MainActor
  private func checkMonday(_ app: XCUIApplication, _ visits: [String]) {
    let weight = app.element("data.weight.open")
    XCTAssertTrue(weight.waitForExistence(timeout: 10), "no Weight row")
    for _ in 0..<3 where !weight.isHittable { app.swipeDown() }
    for id in ["data.weight.open", "metric.week.0", "metric.day.0.open"] {
      let element = app.element(id)
      XCTAssertTrue(element.waitForExistence(timeout: 10), "no \(id)")
      element.tap()
    }
    for (index, label) in visits.enumerated() {
      wait(app.element("day.timeline.visit.\(index)"), "label == '\(label)'")
    }
    for id in ["metric.day.back", "metric.back", "metric.close"] {
      let element = app.element(id)
      XCTAssertTrue(element.waitForExistence(timeout: 10), "no \(id)")
      element.tap()
    }
  }

  @MainActor
  private func wait(_ element: XCUIElement, _ format: String) {
    let met = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
    let result = XCTWaiter().wait(for: [met], timeout: 15)
    XCTAssertEqual(result, .completed, "\(format): \(element.exists ? element.label : "(gone)")")
  }
}
