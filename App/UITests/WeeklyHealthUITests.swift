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

  /// S-027: below the S-022 rows, blood oxygen, respiratory rate and temperature, each labelled
  /// context with its coverage; Sources lists each new type with its app and sample count; with no
  /// samples each value is "--" beside its coverage, never 0.
  @MainActor
  func testStrapContextRowsShowCoverage() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "data-week")

    // Step 1: 0 taps past Data. Oxygen 6 readings, breathing 5 nights, temperature 4 nights.
    let dataCard = app.element("home.card.data")
    XCTAssertTrue(dataCard.waitForExistence(timeout: 30), "no Data card on Home")
    dataCard.tap()
    let oxygen = app.element("data.oxygen.coverage")
    XCTAssertTrue(oxygen.waitForExistence(timeout: 10), "no Blood oxygen row")
    XCTAssertTrue(waitForLabel(oxygen, "6 samples"), "oxygen coverage: \(oxygen.label)")
    XCTAssertEqual(app.element("data.oxygen.value").label, "97%")
    XCTAssertEqual(app.element("data.respiratory.value").label, "14.4 br/min")
    XCTAssertEqual(app.element("data.respiratory.coverage").label, "5 of 7 nights")
    XCTAssertEqual(app.element("data.temperature.value").label, "97.8 °F")
    XCTAssertEqual(app.element("data.temperature.coverage").label, "4 of 7 nights")
    for metric in ["oxygen", "respiratory", "temperature"] {
      XCTAssertEqual(app.element("data.\(metric).context").label, "context", "\(metric) context")
    }
    XCTAssertEqual(app.element("data.steps.coverage").label, "6 of 7 days", "S-022 rows remain")
    XCTAssertFalse(app.element("data.health.hint").exists, "hint shown with every metric present")
    app.scrollViews.firstMatch.swipeUp()
    saveScreenshot("s027-strap-rows", of: app)

    // Step 3: Sources lists each new type with its app and sample count.
    app.element("data.sources").tap()
    let oxygenSource = app.element("sources.row.oxygenSaturation.recent")
    XCTAssertTrue(oxygenSource.waitForExistence(timeout: 10), "no Blood oxygen on Sources")
    XCTAssertTrue(waitForLabel(oxygenSource, "Last 7 days: 6 samples (Strap 6)"))
    XCTAssertEqual(
      app.element("sources.row.respiratoryRate.recent").label, "Last 7 days: 5 samples (Strap 5)")
    XCTAssertEqual(
      app.element("sources.row.bodyTemperature.recent").label, "Last 7 days: 4 samples (Strap 4)")
    XCTAssertEqual(app.element("sources.row.wristTemperature.status").label, "--")

    // Step 4: no samples this week: "--" beside the coverage, never 0.
    app.terminate()
    let empty = UITestApp.launch()
    empty.element("home.card.data").tap()
    let connect = empty.element("data.connect")
    XCTAssertTrue(connect.waitForExistence(timeout: 10))
    connect.tap()
    let emptyOxygen = empty.element("data.oxygen.coverage")
    XCTAssertTrue(emptyOxygen.waitForExistence(timeout: 10), "no Blood oxygen row")
    XCTAssertTrue(waitForLabel(emptyOxygen, "0 samples"), "oxygen coverage: \(emptyOxygen.label)")
    for metric in ["oxygen", "respiratory", "temperature"] {
      XCTAssertEqual(empty.element("data.\(metric).value").label, "--", "\(metric) is not --")
    }
    XCTAssertEqual(empty.element("data.respiratory.coverage").label, "0 of 7 nights")
    XCTAssertEqual(empty.element("data.temperature.coverage").label, "0 of 7 nights")
    XCTAssertTrue(empty.element("data.health.hint").exists, "no Sources hint")
  }

  @MainActor
  private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
    let match = NSPredicate(format: "label == %@", label)
    return XCTWaiter().wait(for: [expectation(for: match, evaluatedWith: element)], timeout: 10)
      == .completed
  }
}
