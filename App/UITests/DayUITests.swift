import XCTest

/// S-041: with the data-food-week scenario (Sunday 2026-01-11 clock, synthetic records) Monday's
/// Day view opens with the day's totals and a timeline: the night, a weigh-in, two meals, the
/// workout and two visits with their times (place names are left for a later card). Empty hours
/// fold, the arrows move a day, tapping a meal scrolls the record list to its row, and tapping the
/// night opens it on the Sleep screen.
final class DayUITests: XCTestCase {
  @MainActor
  func testTimelineSummaryArrowsAndScrollToMeal() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "data-food-week")
    openMonday(app)

    // The summary: time asleep, the kcal and protein ranges, the workout, steps and visits.
    let summary = app.element("day.summary")
    XCTAssertTrue(wait(summary, "label CONTAINS 'Slept 7h 20m'"), "summary: \(summary.label)")
    for total in ["1,200–1,600 kcal, 60–80 g protein", ", 3 sets", "Steps 8,000, visits 2"] {
      XCTAssertTrue(summary.label.contains(total), "summary lacks \(total): \(summary.label)")
    }

    // The timeline: the night with its stages, the weigh-in, both meals, the workout, the visits.
    let marks = [
      ("sleep", "23:00 to 06:45, 7h 20m asleep"), ("weigh-in.0", "07:00, 170.6 lb"),
      ("meal.0", "12:00, 500–700 kcal"), ("meal.1", "12:00, 700–900 kcal"),
      ("workout.0", "18:00, 3 working sets"), ("visit.0", "08:00–11:50"),
      ("visit.1", "12:10–17:50"),
    ]
    for (id, text) in marks {
      let label = app.element("day.timeline.\(id)").label
      XCTAssertTrue(label.contains(text), "\(id): \(label)")
    }

    // Hours with something in them are labelled; empty hours fold to a band without a label.
    for hour in [0, 3, 6, 12, 18] {
      XCTAssertTrue(app.element("day.timeline.hour.\(hour)").exists, "hour \(hour) not open")
    }
    for hour in [9, 15, 21] {
      XCTAssertFalse(app.element("day.timeline.hour.\(hour)").exists, "hour \(hour) not folded")
    }
    // Midnight to noon is 12 open hours of 40 points unfolded; 08:00 to 12:00 fold.
    let (night, lunch) = (app.element("day.timeline.sleep"), app.element("day.timeline.meal.0"))
    XCTAssertLessThan(lunch.frame.minY - night.frame.minY, 11 * 40, "08:00 to 12:00 did not fold")
    saveScreenshot("s041-day-light", of: app)

    // Tapping the larger meal scrolls the record list to its row.
    let row = app.element("day.record.2")
    XCTAssertFalse(row.isHittable, "the meal's row is already on screen")
    app.element("day.timeline.meal.1").tap()
    XCTAssertTrue(wait(row, "isHittable == true"), "the list did not scroll to the meal")
    XCTAssertEqual(
      app.element("day.record.2.detail").label, "Grain Bowl: 700-900 kcal, 40-50 g protein")

    // The arrows move a day: Tuesday has one meal, no workout and no visits.
    app.element("day.next").tap()
    XCTAssertTrue(wait(app.element("metric.title"), "label BEGINSWITH 'Tuesday'"), "not Tuesday")
    XCTAssertTrue(wait(summary, "label CONTAINS 'Food 700–900 kcal'"), summary.label)
    XCTAssertTrue(summary.label.contains("Training --"), summary.label)
    XCTAssertTrue(summary.label.contains("visits --"), summary.label)
    XCTAssertFalse(app.element("day.timeline.workout.0").exists, "a workout invented on Tuesday")
    app.element("day.previous").tap()
    XCTAssertTrue(wait(app.element("metric.title"), "label BEGINSWITH 'Monday'"), "not Monday")

    // Tapping the night opens it on the Sleep screen.
    app.element("day.timeline.sleep").tap()
    let picked = app.element("sleep.night")
    XCTAssertTrue(wait(picked, "label BEGINSWITH 'Monday'"), "Sleep opened \(picked.label)")
    app.element("sleep.close").tap()

    let dark = UITestApp.launch(scenario: "data-food-week", dark: true)
    openMonday(dark)
    XCTAssertTrue(wait(dark.element("day.summary"), "label CONTAINS 'visits 2'"), "dark: no visits")
    saveScreenshot("s041-day-dark", of: dark)
  }

  /// Data, Weight, this week, Monday: S-025's path into the Day view.
  @MainActor
  private func openMonday(_ app: XCUIApplication) {
    let dataCard = app.element("home.card.data")
    XCTAssertTrue(dataCard.waitForExistence(timeout: 30), "no Data card on Home")
    dataCard.tap()
    for id in ["data.weight.open", "metric.week.0", "metric.day.0.open"] {
      let element = app.element(id)
      XCTAssertTrue(element.waitForExistence(timeout: 10), "no \(id)")
      element.tap()
    }
    XCTAssertTrue(app.element("day.timeline.sleep").waitForExistence(timeout: 10), "no timeline")
  }

  @MainActor
  private func wait(_ element: XCUIElement, _ format: String) -> Bool {
    let match = NSPredicate(format: format)
    return XCTWaiter().wait(for: [expectation(for: match, evaluatedWith: element)], timeout: 10)
      == .completed
  }
}
