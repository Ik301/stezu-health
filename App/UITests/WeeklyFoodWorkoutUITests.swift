import XCTest

/// S-023: with the data-food-week scenario (clock pinned to a Sunday, synthetic meals, Stezu
/// sessions and Health workouts) Data's Food row shows the week's mean kcal and protein as ranges
/// over the 5 logged days, and the Workouts row merges both sources, each marked; a week with no
/// meals and no workouts shows "--".
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
    XCTAssertTrue(waitForLabel(coverage, "logged 5 of 7 days"), "food coverage: \(coverage.label)")
    XCTAssertEqual(app.element("data.food.kcal").label, "1000-1320 kcal")
    XCTAssertEqual(app.element("data.food.protein").label, "52-68 g protein")

    // Step 2: Saturday's watch workout, Thursday's and Monday's Stezu sessions, newest first;
    // Finish's copy of Monday's session in Health is not shown twice.
    let total = app.element("data.workouts.value")
    XCTAssertTrue(waitForLabel(total, "3 this week"), "workouts: \(total.label)")
    XCTAssertTrue(app.element("data.workouts.0").label.hasSuffix("Example Watch"))
    XCTAssertEqual(app.element("data.workouts.0.source").label, "Health")
    XCTAssertTrue(app.element("data.workouts.1").label.hasSuffix("2 sets"))
    XCTAssertEqual(app.element("data.workouts.1.source").label, "Stezu")
    XCTAssertTrue(app.element("data.workouts.2").label.hasSuffix("3 sets"))
    XCTAssertEqual(app.element("data.workouts.2.source").label, "Stezu")
    XCTAssertFalse(app.element("data.workouts.3").exists, "a session is shown twice")
    app.scrollViews.firstMatch.swipeUp()
    saveScreenshot("s023-food-workouts", of: app)

    // Step 3: no meals and no workouts this week: "--", never 0.
    app.terminate()
    let empty = UITestApp.launch(scenario: "data-week")
    empty.element("home.card.data").tap()
    let emptyKcal = empty.element("data.food.kcal")
    XCTAssertTrue(emptyKcal.waitForExistence(timeout: 10), "no Food row")
    XCTAssertTrue(
      waitForLabel(empty.element("data.food.coverage"), "logged 0 of 7 days"), "food coverage")
    XCTAssertEqual(emptyKcal.label, "--")
    XCTAssertEqual(empty.element("data.food.protein").label, "--")
    XCTAssertTrue(waitForLabel(empty.element("data.workouts.value"), "--"), "workouts not --")
    XCTAssertFalse(empty.element("data.workouts.0").exists, "a workout in an empty week")
  }

  @MainActor
  private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
    let match = NSPredicate(format: "label == %@", label)
    return XCTWaiter().wait(for: [expectation(for: match, evaluatedWith: element)], timeout: 10)
      == .completed
  }
}
