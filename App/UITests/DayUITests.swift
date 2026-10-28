import XCTest

/// S-041: with the data-food-week scenario (Sunday 2026-01-11 clock, synthetic records) Monday's
/// Day view opens with the day's totals and a timeline: the night, a weigh-in, two meals, the
/// workout and two visits with their times (S-049 adds the fake geocoder's names). Empty hours
/// fold, the arrows move a day, tapping a meal scrolls the record list to its row, and tapping the
/// night opens it on the Sleep screen.
final class DayUITests: XCTestCase {
  @MainActor
  func testTimelineSummaryArrowsAndScrollToMeal() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "data-food-week")
    openMonday(app)

    // The summary: time asleep, the kcal and protein ranges, the workout and steps. S-049 made
    // it a grid of cells and moved the visits count to the timeline's visits.
    let (slept, food) = (app.element("day.summary.slept"), app.element("day.summary.food"))
    XCTAssertTrue(wait(slept, "label == 'Slept 7h 20m'"), "slept: \(slept.label)")
    XCTAssertEqual(food.label, "Food 1,200–1,600 kcal, 60–80 g protein")
    let training = app.element("day.summary.training")
    XCTAssertTrue(training.label.hasSuffix(" 3 sets"), "training: \(training.label)")
    XCTAssertEqual(app.element("day.summary.steps").label, "Steps 8,000")

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
      app.element("day.record.2.detail").label, "Grain Bowl: 700–900 kcal, 40–50 g protein")

    // The arrows move a day: Tuesday has one meal, no workout and no visits.
    app.element("day.next").tap()
    XCTAssertTrue(wait(app.element("metric.title"), "label BEGINSWITH 'Tuesday'"), "not Tuesday")
    XCTAssertTrue(wait(food, "label BEGINSWITH 'Food 700–900 kcal'"), food.label)
    XCTAssertTrue(wait(training, "label == 'Training --'"), training.label)
    XCTAssertTrue(wait(app.element("day.timeline.visit.0"), "exists == false"), "Tuesday visit")
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
    XCTAssertTrue(
      dark.element("day.timeline.visit.1").waitForExistence(timeout: 10), "dark: visits")
    saveScreenshot("s041-day-dark", of: dark)
  }

  /// S-049: the fake geocoder names Monday's visits; the summary is four cells; the date is the
  /// large title under the arrows, which still move a day; the timeline has Where and What.
  @MainActor
  func testPlaceNamesAndSummaryGrid() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "data-food-week")
    openMonday(app)

    let (library, hall) = (app.element("day.timeline.visit.0"), app.element("day.timeline.visit.1"))
    XCTAssertTrue(wait(library, "label == 'Library, 08:00–11:50'"), "visit 0: \(library.label)")
    XCTAssertEqual(hall.label, "Dining hall, 12:10–17:50")
    XCTAssertTrue(app.staticTexts["Where"].exists, "no Where header")
    XCTAssertTrue(app.staticTexts["What"].exists, "no What header")

    let cells = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'day.summary.'"))
    XCTAssertEqual(cells.count, 4, "the summary is not four cells")
    for (id, label) in [
      ("slept", "Slept 7h 20m"), ("food", "Food 1,200–1,600 kcal, 60–80 g protein"),
      ("steps", "Steps 8,000"),
    ] {
      XCTAssertEqual(app.element("day.summary.\(id)").label, label)
    }
    XCTAssertTrue(app.element("day.summary.training").label.hasPrefix("Training "))
    XCTAssertTrue(app.element("day.summary.training").label.hasSuffix(" 3 sets"))

    // The arrows sit in the row above the date, and still move a day.
    let (title, next) = (app.element("metric.title"), app.element("day.next"))
    XCTAssertLessThan(next.frame.maxY, title.frame.midY, "the arrows are not above the date")
    XCTAssertLessThan(app.element("day.previous").frame.minX, next.frame.minX)
    saveScreenshot("s049-day", of: app)

    next.tap()
    XCTAssertTrue(wait(title, "label BEGINSWITH 'Tuesday'"), "not Tuesday: \(title.label)")
    let training = app.element("day.summary.training")
    XCTAssertTrue(wait(training, "label == 'Training --'"), "Tuesday: \(training.label)")
    XCTAssertTrue(wait(library, "exists == false"), "Tuesday has no visits")
    app.element("day.previous").tap()
    XCTAssertTrue(wait(title, "label BEGINSWITH 'Monday'"), "not Monday: \(title.label)")
    XCTAssertTrue(wait(library, "label == 'Library, 08:00–11:50'"), "visit 0: \(library.label)")
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
