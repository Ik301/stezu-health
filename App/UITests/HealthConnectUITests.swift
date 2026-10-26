import XCTest

/// S-020: the first open of Data shows the Connect empty state, one tap asks Health once, Data
/// then opens straight to the overview, and Sources lists every type. FakeHealthStore has no
/// samples, so every type is absent and shows "--" with the hint.
final class HealthConnectUITests: XCTestCase {
  @MainActor
  func testFirstOpenConnectsOnceAndShowsSources() {
    continueAfterFailure = false
    let app = UITestApp.launch()

    // Step 1: the first tap on Data shows the empty state with one Connect button.
    let dataCard = app.element("home.card.data")
    XCTAssertTrue(dataCard.waitForExistence(timeout: 30), "no Data card on Home")
    dataCard.tap()
    XCTAssertTrue(app.element("screen.data.title").waitForExistence(timeout: 10))
    let connect = app.element("data.connect")
    XCTAssertTrue(connect.waitForExistence(timeout: 10), "no Connect Apple Health button")
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Ingest reads'")).firstMatch
        .exists, "the empty state does not say what Ingest reads")
    XCTAssertFalse(app.element("data.sources").exists, "the overview shows before Connect")
    saveScreenshot("s020-connect", of: app)

    // Step 2: Connect, then the overview; leaving and reopening Data skips the empty state.
    connect.tap()
    let sources = app.element("data.sources")
    XCTAssertTrue(sources.waitForExistence(timeout: 10), "no overview after Connect")
    XCTAssertFalse(app.element("data.connect").exists, "the empty state is still there")
    app.element("nav.home").tap()
    XCTAssertTrue(dataCard.waitForExistence(timeout: 10))
    dataCard.tap()
    XCTAssertTrue(sources.waitForExistence(timeout: 10), "Data did not reopen to the overview")
    XCTAssertFalse(app.element("data.connect").exists, "the empty state came back")
    saveScreenshot("s020-overview-empty", of: app)

    // Step 3: one tap to Sources; every type is absent with "--" and the hint.
    sources.tap()
    XCTAssertTrue(app.element("screen.sources.title").waitForExistence(timeout: 10))
    let weight = app.element("sources.row.bodyMass.status")
    XCTAssertTrue(weight.waitForExistence(timeout: 10), "no Weight row")
    XCTAssertEqual(weight.label, "--")
    XCTAssertTrue(app.element("sources.row.bodyMass.hint").exists, "no denied-read hint")
    XCTAssertTrue(app.element("sources.row.heartRateVariability.status").exists, "no HRV row")
    XCTAssertTrue(app.element("sources.notInHealth").exists, "no Not in Health list")
    saveScreenshot("s020-sources", of: app)
  }
}
