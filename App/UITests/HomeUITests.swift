import XCTest

/// S-037: Home's three GlanceCards. Data leads with last night's sleep, the usual night and the
/// week's trend weight; Food shows today's kcal range; Workout shows this week's sessions with
/// the trained days, the next template and the working sets. Each whole card is the button.
final class HomeUITests: XCTestCase {
  @MainActor
  func testGlanceCardsShowSleepFoodAndWeek() {
    continueAfterFailure = false
    // Step 7: home-week (all synthetic): a Sunday-noon clock, nights ending Mon, Tue, Wed, Fri
    // and Sat of 7h 20m and last night of 6h 15m, five weigh-ins, two meals today, Stezu
    // sessions Monday (3 sets) and Thursday (2 sets) and a Health run Saturday.
    let app = UITestApp.launch(scenario: "home-week")
    let data = app.element("home.card.data")
    XCTAssertTrue(data.waitForExistence(timeout: 30), "no Data card on Home")

    // Steps 1 and 3: each card is one element read as "<area>, <time frame>, <number>, <left
    // fact>, <right fact>".
    XCTAssertTrue(
      waitFor(
        data, "label BEGINSWITH %@",
        "Data, Last night, 6 hours 15 minutes asleep, Usual 7h 20m, Weight "),
      "data: \(data.label)")
    XCTAssertTrue(data.label.hasSuffix(" lb"), "no trend weight: \(data.label)")
    XCTAssertFalse(data.label.hasSuffix("Weight --"), "no trend weight: \(data.label)")
    // Step 4: today's kcal range with an en dash, protein and meals below.
    let food = app.element("home.card.food")
    XCTAssertEqual(food.label, "Food, Today, 1,200–1,600 kcal, 60–80 g protein, 2 meals")
    // Step 5: sessions with the days they fall on, the next template and the week's sets.
    let workout = app.element("home.card.workout")
    XCTAssertEqual(
      workout.label, "Workout, This week, 3 sessions (Mon, Thu, Sat), Next: Day 1 Push, 5 sets")
    for card in [data, food, workout] {
      let text = card.label.lowercased()
      XCTAssertFalse(text.contains("target") || text.contains("score"), "a target: \(text)")
    }

    // Step 2: the three cards share the height evenly, and Home does not scroll.
    let heights = [data, food, workout].map { $0.frame.height }
    XCTAssertLessThan((heights.max() ?? 0) - (heights.min() ?? 0), 2, "heights \(heights)")
    XCTAssertEqual(app.scrollViews.count, 0, "Home scrolls")
    saveScreenshot("s037-home-light", of: app)

    // Step 7: a tap anywhere on the Food card, here near its bottom right, opens the camera.
    food.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.88)).tap()
    XCTAssertTrue(
      app.element("food.camera.preview").waitForExistence(timeout: 10), "no camera after Food")
    app.terminate()

    // Light and Dark follow the phone; -uitest-dark draws the same Home in Dark.
    let dark = UITestApp.launch(scenario: "home-week", dark: true)
    let darkData = dark.element("home.card.data")
    XCTAssertTrue(darkData.waitForExistence(timeout: 30), "no Data card in Dark")
    XCTAssertTrue(
      waitFor(darkData, "label BEGINSWITH %@", "Data, Last night, 6 hours 15 minutes asleep"),
      "dark data: \(darkData.label)")
    saveScreenshot("s037-home-dark", of: dark)
    dark.terminate()

    // Step 7: the empty scenario: every number is "--", never 0.
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
  }

  @MainActor
  private func waitFor(_ element: XCUIElement, _ format: String, _ text: String) -> Bool {
    let match = NSPredicate(format: format, text)
    return XCTWaiter().wait(for: [expectation(for: match, evaluatedWith: element)], timeout: 15)
      == .completed
  }
}
