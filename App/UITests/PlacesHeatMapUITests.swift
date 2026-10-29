import XCTest

/// Places' heat map: the map shows the made-up "location" log, a tap on a visit opens its spot
/// with the looked-up name, and a label saved there renames the visit in the list.
final class PlacesHeatMapUITests: XCTestCase {
  @MainActor
  func testHeatMapSpotTakesALabel() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "location")

    let card = app.element("home.card.data")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Data card on Home")
    card.tap()
    let row = app.element("data.places.open")
    XCTAssertTrue(row.waitForExistence(timeout: 10), "the Places row is not a button")
    for _ in 0..<3 where !row.isHittable { app.swipeUp() }
    row.tap()
    XCTAssertTrue(app.element("places.map").waitForExistence(timeout: 10), "no heat map")

    let library = app.element("places.visit.1.name")
    XCTAssertTrue(library.waitForExistence(timeout: 10), "no older visit listed")
    wait(for: "label == 'Library'", on: library)
    app.element("places.visit.1").tap()
    let name = app.element("places.spot.name")
    XCTAssertTrue(name.waitForExistence(timeout: 10), "the spot did not open")
    XCTAssertEqual(name.label, "Library")
    saveScreenshot("places-heatmap", of: app)

    let field = app.element("places.spot.field")
    field.tap()
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "Study room")
    app.element("places.spot.save").tap()
    wait(for: "label == 'Study room'", on: library)
    wait(for: "label == 'Study room'", on: name)
    XCTAssertEqual(app.element("places.visit.0.name").label, "Dining hall", "another spot changed")
    saveScreenshot("places-label-saved", of: app)
  }

  @MainActor
  private func wait(for format: String, on element: XCUIElement) {
    let met = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
    let result = XCTWaiter().wait(for: [met], timeout: 15)
    XCTAssertEqual(result, .completed, "\(format): \(element.exists ? element.label : "(gone)")")
  }
}
