import XCTest

/// S-024: with the data-week scenario (clock pinned to Sunday 2026-01-11, synthetic samples) one
/// tap on an overview row opens that metric's last 8 weeks with their coverage, then the sources
/// and the evidence note; Weight adds weigh-in dots and the trend line. One tap on a week lists its
/// days, Monday to Sunday, and a day without data shows "--". Steps uses the same template.
final class MetricDetailUITests: XCTestCase {
  @MainActor
  func testMetricWeeksAndDays() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "data-week")
    let dataCard = app.element("home.card.data")
    XCTAssertTrue(dataCard.waitForExistence(timeout: 30), "no Data card on Home")
    dataCard.tap()

    // Step 1: one tap into Weight. 8 weeks, newest first; this week has 5 weigh-in days.
    let openWeight = app.element("data.weight.open")
    XCTAssertTrue(openWeight.waitForExistence(timeout: 10), "no way into Weight")
    openWeight.tap()
    let thisWeek = app.element("metric.week.0")
    XCTAssertTrue(thisWeek.waitForExistence(timeout: 10), "no weeks")
    XCTAssertTrue(waitForLabel(app.element("metric.title"), "Weight"))
    for index in 0..<8 {
      XCTAssertTrue(app.element("metric.week.\(index)").exists, "no week \(index)")
    }
    XCTAssertFalse(app.element("metric.week.8").exists, "more than 8 weeks")
    XCTAssertTrue(thisWeek.label.contains("5 of 7 days"), "this week: \(thisWeek.label)")
    XCTAssertTrue(thisWeek.label.hasPrefix("Mon"), "week does not start Monday: \(thisWeek.label)")
    let lastWeek = app.element("metric.week.1").label
    XCTAssertTrue(lastWeek.contains("2 of 7 days"), "last week: \(lastWeek)")
    let oldest = app.element("metric.week.7").label
    XCTAssertTrue(oldest.contains("0 of 7 days") && oldest.hasSuffix("--"), "oldest: \(oldest)")
    XCTAssertTrue(app.element("metric.chart").exists, "no weigh-in dots and trend line")
    XCTAssertEqual(app.element("metric.sources").label, "From: Stezu")
    XCTAssertTrue(app.element("metric.note").label.contains("trend"), "no evidence note")
    saveScreenshot("s024-metric", of: app)

    // Step 2: one tap into this week: Monday to Sunday; Thursday (only the strap) and Sunday "--".
    thisWeek.tap()
    let monday = app.element("metric.day.0.name")
    XCTAssertTrue(monday.waitForExistence(timeout: 10), "no days")
    XCTAssertTrue(monday.label.hasPrefix("Mon"), "first day: \(monday.label)")
    XCTAssertTrue(app.element("metric.day.6.name").label.hasPrefix("Sun"))
    XCTAssertFalse(app.element("metric.day.7.name").exists, "more than 7 days")
    XCTAssertEqual(app.element("metric.day.0.value").label, "170.6 lb")
    XCTAssertEqual(app.element("metric.day.3.value").label, "--", "the strap's weight counted")
    XCTAssertEqual(app.element("metric.day.6.value").label, "--")
    saveScreenshot("s024-week-days", of: app)

    // The same template for Steps: back to the overview, one tap, one tap.
    app.element("metric.back").tap()
    let close = app.element("metric.close")
    XCTAssertTrue(close.waitForExistence(timeout: 10), "no way back to the weeks")
    close.tap()
    XCTAssertTrue(wait(close, NSPredicate(format: "exists == false")), "the detail did not close")
    let openSteps = app.element("data.steps.open")
    XCTAssertTrue(openSteps.waitForExistence(timeout: 10), "no way into Steps")
    openSteps.tap()
    XCTAssertTrue(waitForLabel(app.element("metric.title"), "Steps"), "Steps did not open")
    let stepsWeek = app.element("metric.week.0")
    XCTAssertTrue(waitForContains(stepsWeek, "6 of 7 days"), "steps week: \(stepsWeek.label)")
    XCTAssertEqual(app.element("metric.sources").label, "From: Phone")
    XCTAssertFalse(app.element("metric.chart").exists, "only Weight has the chart")
    stepsWeek.tap()
    let stepsMonday = app.element("metric.day.0.value")
    XCTAssertTrue(waitForLabel(stepsMonday, "8000"), "Monday steps: \(stepsMonday.label)")
    XCTAssertEqual(app.element("metric.day.6.value").label, "--")
  }

  @MainActor
  private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
    wait(element, NSPredicate(format: "label == %@", label))
  }

  @MainActor
  private func waitForContains(_ element: XCUIElement, _ text: String) -> Bool {
    wait(element, NSPredicate(format: "label CONTAINS %@", text))
  }

  @MainActor
  private func wait(_ element: XCUIElement, _ predicate: NSPredicate) -> Bool {
    XCTWaiter().wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 10)
      == .completed
  }
}
