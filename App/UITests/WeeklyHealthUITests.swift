import XCTest

/// S-022: with the data-week scenario (clock pinned to a Sunday, synthetic samples) Data shows
/// steps, sleep, HRV and resting heart rate for the week, each with its coverage, sleep and HRV
/// labelled context; with no samples every value is "--" beside its coverage.
final class WeeklyHealthUITests: XCTestCase {
  @MainActor
  func testHealthRowsShowCoverage() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "data-week")

    // Step 1: 0 taps past Data. Steps on 6 days, sleep 5 nights, HRV 5 readings, RHR 5 days.
    let dataCard = app.element("home.card.data")
    XCTAssertTrue(dataCard.waitForExistence(timeout: 30), "no Data card on Home")
    dataCard.tap()
    let steps = app.element("data.steps.coverage")
    XCTAssertTrue(steps.waitForExistence(timeout: 10), "no Steps row")
    XCTAssertTrue(waitForLabel(steps, "6 of 7 days"), "steps coverage: \(steps.label)")
    XCTAssertEqual(app.element("data.steps.value").label, "7333")
    XCTAssertEqual(app.element("data.sleep.value").label, "7h 20m")
    XCTAssertEqual(app.element("data.sleep.coverage").label, "5 of 7 nights")
    XCTAssertEqual(app.element("data.sleep.context").label, "context")
    XCTAssertEqual(app.element("data.hrv.value").label, "47 ms")
    XCTAssertEqual(app.element("data.hrv.coverage").label, "5 samples")
    XCTAssertEqual(app.element("data.hrv.context").label, "context")
    XCTAssertEqual(app.element("data.restingHR.value").label, "59 bpm")
    XCTAssertEqual(app.element("data.restingHR.coverage").label, "5 of 7 days")
    XCTAssertFalse(app.element("data.restingHR.context").exists, "resting HR is not context")
    XCTAssertFalse(app.element("data.health.hint").exists, "hint shown with every metric present")
    saveScreenshot("s022-health-rows", of: app)

    // Step 3: no samples this week: every value is "--" beside its coverage, never 0.
    app.terminate()
    let empty = UITestApp.launch()
    empty.element("home.card.data").tap()
    let connect = empty.element("data.connect")
    XCTAssertTrue(connect.waitForExistence(timeout: 10))
    connect.tap()
    let emptySteps = empty.element("data.steps.coverage")
    XCTAssertTrue(emptySteps.waitForExistence(timeout: 10), "no Steps row")
    XCTAssertTrue(waitForLabel(emptySteps, "0 of 7 days"), "steps coverage: \(emptySteps.label)")
    for metric in ["steps", "sleep", "hrv", "restingHR"] {
      XCTAssertEqual(empty.element("data.\(metric).value").label, "--", "\(metric) is not --")
    }
    XCTAssertEqual(empty.element("data.sleep.coverage").label, "0 of 7 nights")
    XCTAssertEqual(empty.element("data.hrv.coverage").label, "0 samples")
    XCTAssertTrue(empty.element("data.health.hint").exists, "no Sources hint")
  }

  @MainActor
  private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
    let match = NSPredicate(format: "label == %@", label)
    return XCTWaiter().wait(for: [expectation(for: match, evaluatedWith: element)], timeout: 10)
      == .completed
  }
}
