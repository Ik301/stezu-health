import XCTest

/// S-026: with 0 taps, Home shows the trend weight this week, today's food as ranges with the
/// meal count, and this week's sessions with the next template; no target anywhere (D-032).
/// Without data every card shows "--", never 0. S-037 (D-097) moved the cards to GlanceCard:
/// Data leads with last night's sleep and keeps the trend weight small, and each label now
/// reads "<area>, <time frame>, <number>, <left fact>, <right fact>".
final class HomeCardsUITests: XCTestCase {
  @MainActor
  func testHomeCardsShowTodayAndThisWeek() {
    continueAfterFailure = false
    // Step 1: home-week is data-food-week (Sunday clock, 5 weigh-in days, sessions Monday and
    // Thursday, a Health run Saturday) plus two meals today. All synthetic.
    let app = UITestApp.launch(scenario: "home-week")
    let data = app.element("home.card.data")
    XCTAssertTrue(data.waitForExistence(timeout: 30), "no Data card on Home")

    // Step 2: 0 taps.
    XCTAssertTrue(
      waitFor(data, "label BEGINSWITH %@", "Data, Last night, 6 hours 15 minutes asleep, "),
      "data: \(data.label)")
    XCTAssertTrue(data.label.hasSuffix(" lb"), "no trend weight: \(data.label)")
    let food = app.element("home.card.food")
    XCTAssertTrue(
      waitFor(food, "label == %@", "Food, Today, 1,200–1,600 kcal, 60–80 g protein, 2 meals"),
      "food: \(food.label)")
    let workout = app.element("home.card.workout")
    XCTAssertTrue(
      waitFor(
        workout, "label BEGINSWITH %@",
        "Workout, This week, 3 sessions (Mon, Thu, Sat), Next: Day 1 Push, "),
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
      waitFor(
        emptyWorkout, "label == %@", "Workout, This week, -- sessions, Next: Day 1 Push, -- sets"),
      "workout: \(emptyWorkout.label)")
    XCTAssertEqual(
      empty.element("home.card.data").label, "Data, Last night, --, Usual --, Weight --")
    XCTAssertEqual(
      empty.element("home.card.food").label, "Food, Today, -- kcal, -- g protein, -- meals")
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
