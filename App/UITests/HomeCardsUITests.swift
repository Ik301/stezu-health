import XCTest

/// S-026: with 0 taps, Home shows the trend weight and weigh-ins this week, today's food as
/// ranges with the meal count, and this week's sessions with the next template; no target
/// anywhere (D-032). Without data every card shows "--", never 0.
final class HomeCardsUITests: XCTestCase {
  @MainActor
  func testHomeCardsShowTodayAndThisWeek() {
    continueAfterFailure = false
    // Step 1: home-week is data-food-week (Sunday clock, 5 weigh-in days, sessions Monday and
    // Thursday, a Health run Saturday) plus two meals today. All synthetic.
    let app = UITestApp.launch(scenario: "home-week")
    let data = app.element("home.card.data")
    XCTAssertTrue(data.waitForExistence(timeout: 30), "no Data card on Home")

    // Step 2: 0 taps. Each card's label is "<label>, <subtitle>, <number>".
    XCTAssertTrue(
      waitFor(data, "label BEGINSWITH %@", "Data, Trend weight, lb. Weigh-ins 5 of 7, "),
      "data: \(data.label)")
    XCTAssertFalse(data.label.hasSuffix(", --"), "no trend weight: \(data.label)")
    let food = app.element("home.card.food")
    XCTAssertTrue(
      waitFor(food, "label == %@", "Food, Today, kcal. 60-80 g protein, 2 meals, 1200-1600"),
      "food: \(food.label)")
    let workout = app.element("home.card.workout")
    XCTAssertTrue(
      waitFor(workout, "label == %@", "Workout, Sessions this week. Next: Day 1 Push, 3"),
      "workout: \(workout.label)")
    for card in [data, food, workout] {
      let text = card.label.lowercased()
      XCTAssertFalse(text.contains("target") || text.contains("remaining"), "a target: \(text)")
    }
    saveScreenshot("s026-home-filled", of: app)

    // Step 3: no data: every number is "--", never 0.
    app.terminate()
    let empty = UITestApp.launch()
    let emptyWorkout = empty.element("home.card.workout")
    XCTAssertTrue(emptyWorkout.waitForExistence(timeout: 30), "no Workout card on Home")
    XCTAssertTrue(
      waitFor(emptyWorkout, "label == %@", "Workout, Sessions this week. Next: Day 1 Push, --"),
      "workout: \(emptyWorkout.label)")
    XCTAssertEqual(
      empty.element("home.card.data").label, "Data, Trend weight, lb. Weigh-ins --, --")
    XCTAssertEqual(
      empty.element("home.card.food").label, "Food, Today, kcal. -- g protein, -- meals, --")
    for area in ["data", "food", "workout"] {
      XCTAssertFalse(empty.element("home.card.\(area)").label.contains(" 0"), "\(area) shows 0")
    }
    saveScreenshot("s026-home-empty", of: empty)
  }

  @MainActor
  private func waitFor(_ element: XCUIElement, _ format: String, _ text: String) -> Bool {
    let match = NSPredicate(format: format, text)
    return XCTWaiter().wait(for: [expectation(for: match, evaluatedWith: element)], timeout: 15)
      == .completed
  }
}
