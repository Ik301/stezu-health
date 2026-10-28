import XCTest

/// S-032: with Always access the fake location source delivers two visits (the first one twice,
/// arriving and then departing) and one significant change at launch. Data's Places row shows
/// 2 visits on 1 of 7 days, Sources shows Location as Always with a last-location time, and the
/// fake server holds 3 live records: the departure replaced its visit instead of adding one.
final class LocationUITests: XCTestCase {
  @MainActor
  func testVisitsAppearAndSync() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "location")

    // Data: the Places row counts this week's visits and the days with location data.
    let card = app.element("home.card.data")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Data card on Home")
    card.tap()
    XCTAssertTrue(app.element("screen.data.title").waitForExistence(timeout: 10))
    let places = app.element("data.places.value")
    XCTAssertTrue(places.waitForExistence(timeout: 10), "no Places row")
    // S-048 made Places a MetricRow: the visits are the value, the days its coverage.
    wait(for: "label == '2'", on: places)
    XCTAssertEqual(app.element("data.places.coverage").label, "1 of 7 days")
    for _ in 0..<3 where !places.isHittable { app.swipeUp() }
    saveScreenshot("s032-places-row", of: app)

    // Sources: Location is Always, with the time of the last recorded location.
    app.element("data.sources").tap()
    let status = app.element("sources.location.status")
    XCTAssertTrue(status.waitForExistence(timeout: 10), "no Location row in Sources")
    wait(for: "label == 'Always'", on: status)
    let last = app.element("sources.location.last")
    XCTAssertTrue(last.label.hasPrefix("Last location: "), "last is \(last.label)")
    XCTAssertFalse(last.label.contains("--"), "no last location time: \(last.label)")
    XCTAssertFalse(app.element("sources.location.allow").exists, "Allow shows with Always")
    saveScreenshot("s032-sources-location", of: app)

    // The fake server received the records: two visits and one location, no duplicate.
    app.element("sources.done").tap()
    wait(for: "exists == false", on: status)
    app.element("nav.home").tap()
    let gear = app.element("home.settings")
    XCTAssertTrue(gear.waitForExistence(timeout: 10), "not back on Home")
    gear.tap()
    let row = app.element("settings.sync.status")
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no Hermes sync row")
    wait(for: "label CONTAINS ', 3 records'", on: row)
    XCTAssertFalse(row.label.contains("waiting"), "records still wait: \(row.label)")
  }

  @MainActor
  private func wait(for format: String, on element: XCUIElement) {
    let met = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
    let result = XCTWaiter().wait(for: [met], timeout: 15)
    XCTAssertEqual(result, .completed, "\(format): \(element.exists ? element.label : "(gone)")")
  }
}
