import XCTest

/// S-039: This week follows the walkthrough (design/system/walkthroughs/data.html). With the
/// data-week scenario (Sunday clock, synthetic strap samples) the rows sit in cards with headers,
/// Recovery has one "context only" tag, there is no Blood oxygen or Temperature row, every metric
/// row has a 7-day sparkline, a night without sleep is a dashed slot, and the whole Steps row
/// opens its detail.
final class DataUITests: XCTestCase {
  @MainActor
  func testThisWeekGroupsRowsWithSparklines() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "data-week")
    openData(app)

    // Step 1: the cards, in order, with headers; one "context only" tag, on Recovery.
    let headers = ["Body and activity", "Food and training", "Recovery", "Places"]
    let tops = headers.map { app.staticTexts[$0].firstMatch.frame.minY }
    for (header, top) in zip(headers, tops) {
      XCTAssertTrue(app.staticTexts[header].firstMatch.exists, "no \(header) card")
      XCTAssertGreaterThan(top, 0, "\(header) has no frame")
    }
    XCTAssertEqual(tops, tops.sorted(), "the cards are out of order: \(tops)")
    XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "data.card.tag").count, 1)
    XCTAssertEqual(app.element("data.card.tag").label, "context only")
    XCTAssertGreaterThan(
      app.element("data.sleep.value").frame.minY, app.element("data.card.tag").frame.minY,
      "Sleep is not under the Recovery header")

    // Step 2: no Blood oxygen or Temperature rows (D-093).
    for id in ["oxygen", "temperature"] {
      XCTAssertFalse(app.element("data.\(id).value").exists, "a \(id) row")
      XCTAssertFalse(app.element("data.spark.\(id)").exists, "a \(id) sparkline")
    }
    XCTAssertFalse(app.staticTexts["Blood oxygen"].exists)
    XCTAssertFalse(app.staticTexts["Temperature"].exists)

    // Steps 3 and 4: every metric row has its sparkline; Sleep has no night ending on Thursday
    // or Sunday, so two dashed slots; Steps has none on Sunday.
    let rows = ["weight", "steps", "food", "workouts", "sleep", "hrv", "restingHR", "respiratory"]
    for id in rows {
      XCTAssertTrue(app.element("data.spark.\(id)").exists, "no sparkline on \(id)")
      XCTAssertTrue(app.element("data.\(id).open").exists, "\(id) is not one button")
    }
    XCTAssertEqual(
      app.element("data.spark.sleep").value as? String, "2 of 7 days without data")
    XCTAssertEqual(
      app.element("data.spark.steps").value as? String, "1 of 7 days without data")
    let stepsRow = app.element("data.steps.open")
    XCTAssertGreaterThanOrEqual(stepsRow.frame.height, 44, "the row is under 44 pt")
    XCTAssertGreaterThan(stepsRow.frame.width, app.windows.firstMatch.frame.width / 2)
    saveScreenshot("s039-this-week-light", of: app)

    // Step 5: a tap in the middle of the Steps row, away from the chevron, opens its detail.
    stepsRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    let title = app.element("metric.title")
    XCTAssertTrue(title.waitForExistence(timeout: 10), "the Steps row did not open its detail")
    XCTAssertEqual(title.label, "Steps")

    // Dark follows the phone; the lower cards.
    app.terminate()
    let dark = UITestApp.launch(scenario: "data-week", dark: true)
    openData(dark)
    dark.scrollViews.firstMatch.swipeUp()
    saveScreenshot("s039-this-week-dark", of: dark)
  }

  /// Opens Data and waits until both the first and the last Health rows have loaded.
  @MainActor
  private func openData(_ app: XCUIApplication) {
    let card = app.element("home.card.data")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Data card on Home")
    card.tap()
    for (id, label) in [("steps", "6 of 7 days"), ("respiratory", "5 of 7 nights")] {
      let coverage = app.element("data.\(id).coverage")
      let match = NSPredicate(format: "label == %@", label)
      XCTAssertEqual(
        XCTWaiter().wait(for: [expectation(for: match, evaluatedWith: coverage)], timeout: 10),
        .completed, "\(id) coverage: \(coverage.label)")
    }
  }
}
