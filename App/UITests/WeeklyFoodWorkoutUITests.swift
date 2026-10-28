import XCTest

/// S-023: with the data-food-week scenario (clock pinned to a Sunday, synthetic meals, Stezu
/// sessions and Health workouts) Data's Food row shows the week's mean kcal and protein as ranges
/// over the 5 logged days, and the Workouts row merges both sources, each marked; a week with no
/// meals and no workouts shows "--". Since S-039 both are MetricRows: Food shows the kcal range
/// (protein moved to its detail), Workouts the session count with the week's working sets beneath,
/// and the per-session list left the overview.
final class WeeklyFoodWorkoutUITests: XCTestCase {
  @MainActor
  func testFoodAndWorkoutRows() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "data-food-week")

    // Step 1: 0 taps past Data. Mean of 5 logged days, as ranges.
    let dataCard = app.element("home.card.data")
    XCTAssertTrue(dataCard.waitForExistence(timeout: 30), "no Data card on Home")
    dataCard.tap()
    let coverage = app.element("data.food.coverage")
    XCTAssertTrue(coverage.waitForExistence(timeout: 10), "no Food row")
    XCTAssertTrue(waitForLabel(coverage, "5 of 7 days"), "food coverage: \(coverage.label)")
    XCTAssertEqual(app.element("data.food.value").label, "1,000–1,320 kcal")

    // Step 2: Saturday's watch workout, Thursday's and Monday's Stezu sessions: 3; Finish's copy
    // of Monday's session in Health is not counted twice. Working sets are Stezu's: 3 + 2.
    let total = app.element("data.workouts.value")
    XCTAssertTrue(waitForLabel(total, "3"), "workouts: \(total.label)")
    XCTAssertEqual(app.element("data.workouts.coverage").label, "5 working sets")
    app.scrollViews.firstMatch.swipeUp()
    saveScreenshot("s023-food-workouts", of: app)

    // Step 3: no meals and no workouts this week: "--", never 0.
    app.terminate()
    let empty = UITestApp.launch(scenario: "data-week")
    empty.element("home.card.data").tap()
    let emptyKcal = empty.element("data.food.value")
    XCTAssertTrue(emptyKcal.waitForExistence(timeout: 10), "no Food row")
    XCTAssertTrue(
      waitForLabel(empty.element("data.food.coverage"), "0 of 7 days"), "food coverage")
    XCTAssertEqual(emptyKcal.label, "--")
    XCTAssertTrue(waitForLabel(empty.element("data.workouts.value"), "--"), "workouts not --")
    XCTAssertEqual(empty.element("data.workouts.coverage").label, "--", "sets in an empty week")
  }

  @MainActor
  private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
    let match = NSPredicate(format: "label == %@", label)
    return XCTWaiter().wait(for: [expectation(for: match, evaluatedWith: element)], timeout: 10)
      == .completed
  }
}
