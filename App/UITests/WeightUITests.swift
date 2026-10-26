import XCTest

/// S-021: Data shows this week's Weight row from synthetic Stezu weigh-ins (the data-week
/// scenario pins the clock to a Sunday), one tap opens a prefilled stepper, Save writes one
/// sample and the row updates; with no weigh-ins the row shows "--".
final class WeightUITests: XCTestCase {
  @MainActor
  func testWeightTrendAndOneTapWeighIn() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "data-week")

    // Step 1: 0 taps past Data. The week runs Monday to Sunday; the strap's weight is left out.
    let dataCard = app.element("home.card.data")
    XCTAssertTrue(dataCard.waitForExistence(timeout: 30), "no Data card on Home")
    dataCard.tap()
    let coverage = app.element("data.weight.coverage")
    XCTAssertTrue(coverage.waitForExistence(timeout: 10), "no Weight row")
    XCTAssertTrue(waitForLabel(coverage, "Weigh-ins: 5 of 7"), "coverage: \(coverage.label)")
    XCTAssertTrue(
      app.element("data.week.range").label.hasPrefix("Mon"), "week does not start Monday")
    XCTAssertNotEqual(app.element("data.weight.trend").label, "--")
    XCTAssertTrue(app.element("data.weight.change").label.hasPrefix("This week: -"))
    XCTAssertTrue(app.element("data.weight.reason").label.contains("weigh-ins"))
    XCTAssertEqual(app.element("data.weight.sources").label, "From: Stezu")
    XCTAssertFalse(app.element("data.connect").exists, "the scenario should be connected")
    saveScreenshot("s021-weight", of: app)

    // Step 2: Weigh in, prefilled with Saturday's weigh-in, no keyboard; Save writes one sample.
    app.element("data.weighIn").tap()
    let value = app.element("data.weighIn.value")
    XCTAssertTrue(value.waitForExistence(timeout: 10), "no weigh-in stepper")
    XCTAssertEqual(value.label, "169.8 lb")
    XCTAssertTrue(app.element("data.weighIn.stepper").exists)
    XCTAssertFalse(app.keyboards.firstMatch.exists, "a keyboard showed")
    saveScreenshot("s021-weigh-in", of: app)
    app.element("data.weighIn.save").tap()
    XCTAssertTrue(
      waitForLabel(coverage, "Weigh-ins: 6 of 7"), "row did not update: \(coverage.label)")

    // Step 3: a week with no weigh-ins shows "--".
    app.terminate()
    let empty = UITestApp.launch()
    empty.element("home.card.data").tap()
    let connect = empty.element("data.connect")
    XCTAssertTrue(connect.waitForExistence(timeout: 10))
    connect.tap()
    let trend = empty.element("data.weight.trend")
    XCTAssertTrue(trend.waitForExistence(timeout: 10), "no Weight row")
    XCTAssertEqual(trend.label, "--")
    XCTAssertTrue(waitForLabel(empty.element("data.weight.coverage"), "Weigh-ins: --"))
  }

  @MainActor
  private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
    let match = NSPredicate(format: "label == %@", label)
    return XCTWaiter().wait(for: [expectation(for: match, evaluatedWith: element)], timeout: 10)
      == .completed
  }
}
