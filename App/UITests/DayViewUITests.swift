import XCTest

/// S-025: with the data-food-week scenario (clock pinned to Sunday 2026-01-11, synthetic samples,
/// meals and sessions) one tap on Monday in Weight's current week opens everything recorded that
/// day, each with its source. Stezu's records have Delete (meals also Edit); Health's have none.
final class DayViewUITests: XCTestCase {
  @MainActor
  func testDayListsRecordsWithSources() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "data-food-week")
    let dataCard = app.element("home.card.data")
    XCTAssertTrue(dataCard.waitForExistence(timeout: 30), "no Data card on Home")
    dataCard.tap()
    let openWeight = app.element("data.weight.open")
    XCTAssertTrue(openWeight.waitForExistence(timeout: 10), "no way into Weight")
    openWeight.tap()
    let thisWeek = app.element("metric.week.0")
    XCTAssertTrue(thisWeek.waitForExistence(timeout: 10), "no weeks")
    thisWeek.tap()

    // Step 1: one tap from the week opens Monday with every record and its source.
    let openMonday = app.element("metric.day.0.open")
    XCTAssertTrue(openMonday.waitForExistence(timeout: 10), "no way into Monday")
    openMonday.tap()
    let first = app.element("day.record.0")
    XCTAssertTrue(waitForLabel(first, "Weigh-in"), "first record: \(first.label)")
    XCTAssertTrue(app.element("metric.title").label.hasPrefix("Monday"), "not Monday")
    let expected = [
      ("Weigh-in", "170.6 lb", "From Stezu"),
      ("Meal", "Grain Bowl: 500–700 kcal, 20–30 g protein", "From Stezu"),
      ("Meal", "Grain Bowl: 700–900 kcal, 40–50 g protein", "From Stezu"),
      ("Workout", "Bench press 60 lb x 8, 60 lb x 8, 60 lb x 8", "From Stezu"),
      ("Sleep", "7h 20m asleep", "From Health, read-only"),
      ("HRV", "38 ms", "From Phone, read-only"),
      ("Steps", "8000", "From Phone, read-only"),
    ]
    for (index, record) in expected.enumerated() {
      let id = "day.record.\(index)"
      XCTAssertEqual(app.element(id).label, record.0, id)
      XCTAssertEqual(app.element("\(id).detail").label, record.1, id)
      XCTAssertEqual(app.element("\(id).source").label, record.2, id)
    }
    XCTAssertFalse(app.element("day.record.7").exists, "Finish's Health copy shown twice")

    // Step 2: Stezu's records can be deleted, meals also edited; Health's are read-only.
    for index in 0...3 {
      XCTAssertTrue(app.element("day.record.\(index).delete").exists, "no Delete on \(index)")
    }
    XCTAssertTrue(app.element("day.record.1.edit").exists, "no Edit on a meal")
    XCTAssertFalse(app.element("day.record.0.edit").exists, "Edit on a weigh-in")
    for index in 4...6 {
      XCTAssertFalse(app.element("day.record.\(index).delete").exists, "Health record \(index)")
      XCTAssertFalse(app.element("day.record.\(index).edit").exists, "Health record \(index)")
    }
    saveScreenshot("s025-day", of: app)

    // Edit: a half serving more of the smaller meal, then Log.
    app.element("day.record.1.edit").tap()
    let plus = app.element("food.match.item.0.plus")
    XCTAssertTrue(plus.waitForExistence(timeout: 10), "the meal did not open for editing")
    plus.tap()
    app.element("food.edit.log").tap()
    let edited = app.element("day.record.2.detail")
    XCTAssertTrue(
      waitForLabel(edited, "Grain Bowl: 750–1,050 kcal, 30–45 g protein"), "edit: \(edited.label)")

    // Delete: the first tap asks, the second deletes the weigh-in from Health.
    let delete = app.element("day.record.0.delete")
    delete.tap()
    XCTAssertTrue(waitForLabel(delete, "Confirm"), "no confirm step")
    delete.tap()
    XCTAssertTrue(waitForLabel(first, "Meal"), "the weigh-in was not deleted: \(first.label)")
    XCTAssertEqual(app.element("day.record.5").label, "Steps")
    XCTAssertFalse(app.element("day.record.6").exists, "a record too many after the delete")
  }

  @MainActor
  private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
    let match = NSPredicate(format: "label == %@", label)
    return XCTWaiter().wait(for: [expectation(for: match, evaluatedWith: element)], timeout: 10)
      == .completed
  }
}
