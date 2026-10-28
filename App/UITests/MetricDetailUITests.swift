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

  /// S-042: with data-food-week (Sunday clock; steps this week and on the Saturday before, meals
  /// this week and the Sunday before) Steps draws 8 weekly bars, the older empty weeks as dashed
  /// slots with "--", and a bar opens its week like its row. Food draws energy and protein as two
  /// separate panels. Weight's trend chart is checked in Dark.
  @MainActor
  func testWeekBarsShowAbsentWeekAndFoodPanels() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "data-food-week")
    let dataCard = app.element("home.card.data")
    XCTAssertTrue(dataCard.waitForExistence(timeout: 30), "no Data card on Home")
    dataCard.tap()

    // Steps: one tap, 8 bars, oldest on the left; an empty week is "--", never 0.
    let openSteps = app.element("data.steps.open")
    XCTAssertTrue(openSteps.waitForExistence(timeout: 10), "no way into Steps")
    openSteps.tap()
    XCTAssertTrue(waitForLabel(app.element("metric.title"), "Steps"), "Steps did not open")
    let chart = app.element("metric.weekbars")
    XCTAssertTrue(chart.waitForExistence(timeout: 10), "no WeekBars")
    XCTAssertFalse(chart.label.isEmpty, "the chart has no accessibility label")
    let current = app.element("metric.weekbars.bar.0")
    XCTAssertTrue(waitForContains(current, "6 of 7 days"), "this week's bar: \(current.label)")
    var absent = 0
    for week in 0..<8 {
      let bar = app.element("metric.weekbars.bar.\(week)")
      XCTAssertTrue(bar.exists, "no bar for week \(week)")
      if bar.label.hasSuffix("--") { absent += 1 }
    }
    XCTAssertFalse(app.element("metric.weekbars.bar.8").exists, "more than 8 bars")
    XCTAssertTrue(app.element("metric.weekbars.bar.7").label.contains("0 of 7 days"))
    XCTAssertTrue(app.element("metric.weekbars.bar.7").label.hasSuffix("--"), "oldest not --")
    XCTAssertGreaterThan(absent, 0, "no dashed absent week")
    XCTAssertGreaterThan(
      current.frame.minX, app.element("metric.weekbars.bar.7").frame.minX,
      "the current week is not on the right")
    saveScreenshot("s042-steps-detail", of: app)

    // A bar does what its row does: it opens that week's days.
    current.tap()
    XCTAssertTrue(waitForLabel(app.element("metric.day.0.value"), "8000"), "bar did not open week")
    app.element("metric.back").tap()
    let close = app.element("metric.close")
    XCTAssertTrue(close.waitForExistence(timeout: 10), "no way back to the weeks")
    close.tap()
    XCTAssertTrue(wait(close, NSPredicate(format: "exists == false")), "the detail did not close")

    // Food: energy and protein as two panels, one above the other, never one plot.
    let openFood = app.element("data.food.open")
    XCTAssertTrue(openFood.waitForExistence(timeout: 10), "no way into Food")
    for _ in 0..<3 where !openFood.isHittable { app.swipeUp() }
    openFood.tap()
    XCTAssertTrue(waitForLabel(app.element("metric.title"), "Food"), "Food did not open")
    let energy = app.element("metric.energy")
    let protein = app.element("metric.protein")
    XCTAssertTrue(energy.waitForExistence(timeout: 10), "no energy panel")
    XCTAssertTrue(protein.exists, "no protein panel")
    XCTAssertFalse(energy.label.isEmpty || protein.label.isEmpty, "a panel has no label")
    XCTAssertLessThanOrEqual(energy.frame.maxY, protein.frame.minY, "the panels overlap")
    XCTAssertFalse(app.element("metric.weekbars").exists, "food in one plot")
    let thisWeek = app.element("metric.week.0")
    XCTAssertTrue(waitForContains(thisWeek, "1,000–1,320 kcal, 52–68 g"), "\(thisWeek.label)")
    XCTAssertTrue(app.element("metric.energy.bar.0").label.contains("5 of 7 days"))
    XCTAssertTrue(app.element("metric.protein.bar.2").label.hasSuffix("--"), "empty week not --")
    saveScreenshot("s042-food-detail", of: app)

    // Weight in Dark: the WeekBars well and the weigh-in and trend chart.
    app.terminate()
    let dark = UITestApp.launch(scenario: "data-food-week", dark: true)
    XCTAssertTrue(dark.element("home.card.data").waitForExistence(timeout: 30), "no Data card")
    dark.element("home.card.data").tap()
    let openWeight = dark.element("data.weight.open")
    XCTAssertTrue(openWeight.waitForExistence(timeout: 10), "no way into Weight")
    openWeight.tap()
    XCTAssertTrue(waitForLabel(dark.element("metric.title"), "Weight"), "Weight did not open")
    XCTAssertTrue(dark.element("metric.weekbars").waitForExistence(timeout: 10), "no WeekBars")
    let trend = dark.element("metric.chart")
    XCTAssertTrue(trend.waitForExistence(timeout: 10), "no weight chart")
    XCTAssertTrue(trend.label.contains("weigh-ins"), "weight chart label: \(trend.label)")
    saveScreenshot("s042-weight-detail-dark", of: dark)
  }

  /// S-042b: with data-food-week (Sunday clock; Stezu sessions on Monday with 3 sets and
  /// Thursday with 2, and the Saturday before with 1) the Workouts row opens working sets: this
  /// week 5 over 2 sessions, last week 1, and an empty week "--". Each week but HRV's has its
  /// CoverageDots, filled on the days with sets; a rest day is a real 0.
  @MainActor
  func testWorkoutsDetailShowsSetsAndCoverageDots() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "data-food-week")
    let dataCard = app.element("home.card.data")
    XCTAssertTrue(dataCard.waitForExistence(timeout: 30), "no Data card on Home")
    dataCard.tap()

    let openWorkouts = app.element("data.workouts.open")
    XCTAssertTrue(openWorkouts.waitForExistence(timeout: 10), "no way into Workouts")
    for _ in 0..<3 where !openWorkouts.isHittable { app.swipeUp() }
    openWorkouts.tap()
    XCTAssertTrue(waitForLabel(app.element("metric.title"), "Workouts"), "Workouts did not open")
    let thisWeek = app.element("metric.week.0")
    XCTAssertTrue(waitForContains(thisWeek, "2 sessions"), "this week: \(thisWeek.label)")
    XCTAssertTrue(thisWeek.label.hasSuffix("5 sets"), "this week: \(thisWeek.label)")
    XCTAssertTrue(app.element("metric.week.1").label.hasSuffix("1 set"), "last week's sets")
    let empty = app.element("metric.week.2").label
    XCTAssertTrue(empty.contains("0 sessions") && empty.hasSuffix("--"), "empty week: \(empty)")
    XCTAssertTrue(app.element("metric.weekbars").exists, "no WeekBars")
    XCTAssertTrue(app.element("metric.weekbars.bar.0").label.hasSuffix("5 sets"))
    XCTAssertFalse(app.element("metric.chart").exists, "only Weight has the weight chart")

    // The dots: Monday to Sunday this week, filled on Monday and Thursday.
    let dots = app.element("metric.week.0.dots")
    XCTAssertTrue(dots.exists, "no coverage dots on this week")
    XCTAssertEqual(dots.label, "2 of 7")
    XCTAssertEqual(app.element("metric.week.2.dots").label, "0 of 7")
    XCTAssertLessThan(dots.frame.maxX, thisWeek.frame.minX + 1, "the dots are not before the words")
    saveScreenshot("s042b-workouts-detail", of: app)

    // A week's days: sets on Monday and Thursday, a rest day is 0, not "--".
    thisWeek.tap()
    XCTAssertTrue(waitForLabel(app.element("metric.day.0.value"), "3 sets"), "Monday's sets")
    XCTAssertEqual(app.element("metric.day.1.value").label, "0 sets", "a rest day is a real 0")
    XCTAssertEqual(app.element("metric.day.3.value").label, "2 sets")
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
