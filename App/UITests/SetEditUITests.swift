import XCTest

/// S-055: with the "rotation" fixture (a persisted Day 1 session two days ago, two made-up sets
/// of 60 x 8), a set of a finished session is changed and another deleted from History, and a
/// set is changed from the Day view.
final class SetEditUITests: XCTestCase {
  @MainActor
  func testEditAndDeleteAPastSet() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "rotation", persist: true, reset: true)
    let card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card on Home")
    card.tap()
    tap("workout.history", in: app)
    let session = app.element("history.session.0.0")
    XCTAssertTrue(session.waitForExistence(timeout: 10), "no session in History")
    XCTAssertTrue(session.label.hasSuffix("2 sets"), session.label)
    session.tap()

    // Step 1: each set is its own chip.
    let first = app.element("history.set.0.0")
    let second = app.element("history.set.0.1")
    XCTAssertTrue(second.waitForExistence(timeout: 10), "no set chips")
    XCTAssertEqual(first.label, "60 x 8")
    XCTAssertEqual(second.label, "60 x 8")

    // Step 2: the second set, 5 lb and one rep more, Save; the page shows it at once.
    second.tap()
    let reps = app.element("set.edit.reps")
    XCTAssertTrue(reps.waitForExistence(timeout: 10), "the set did not open")
    XCTAssertEqual(app.element("set.edit.title").label, "Bench press, set 2")
    XCTAssertEqual(app.element("set.edit.weight").label, "60 lb")
    XCTAssertEqual(reps.label, "8")
    app.element("set.edit.weight.plus").tap()
    app.element("set.edit.reps.plus").tap()
    XCTAssertTrue(wait(reps, "9"), reps.label)
    XCTAssertEqual(app.element("set.edit.weight").label, "65 lb")
    saveScreenshot("s055-set-editor", of: app)
    app.element("set.edit.save").tap()
    XCTAssertTrue(wait(second, "65 x 9"), second.label)
    XCTAssertEqual(first.label, "60 x 8")

    // Step 3: delete the first set; the first tap asks, Confirm deletes.
    first.tap()
    let delete = app.element("set.edit.delete")
    XCTAssertTrue(delete.waitForExistence(timeout: 10), "the set did not open")
    XCTAssertEqual(delete.label, "Delete")
    delete.tap()
    XCTAssertTrue(wait(delete, "Confirm"), "no confirm step")
    delete.tap()
    XCTAssertTrue(wait(first, "65 x 9"), first.label)
    XCTAssertFalse(app.element("history.set.0.1").exists, "the deleted set is still shown")
    saveScreenshot("s055-history-edited", of: app)
    app.element("history.session.back").tap()
    XCTAssertTrue(
      XCTWaiter().wait(
        for: [
          expectation(
            for: NSPredicate(format: "label ENDSWITH %@", "   1 set"), evaluatedWith: session)
        ], timeout: 10) == .completed, session.label)
    app.element("workout.history.done").tap()

    // Step 1 again, in the Day view: Data, Workouts, this week, today, then two days back.
    tap("nav.home", in: app)
    tap("home.card.data", in: app)
    let connect = app.element("data.connect")
    if connect.waitForExistence(timeout: 5) { connect.tap() }
    tap("data.workouts.open", in: app)
    tap("metric.week.0", in: app)
    let today = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
    tap("metric.day.\(today).open", in: app)
    tap("day.previous", in: app, up: false)
    tap("day.previous", in: app, up: false)
    let chip = app.element("day.record.0.set.0.0")
    XCTAssertTrue(chip.waitForExistence(timeout: 10), "no set chips in the Day view")
    XCTAssertEqual(chip.label, "65 x 9")
    XCTAssertFalse(app.element("day.record.0.set.0.1").exists, "the deleted set is back")

    // Step 2 from the Day view: one rep fewer, Save.
    tap("day.record.0.set.0.0", in: app)
    XCTAssertTrue(reps.waitForExistence(timeout: 10), "the set did not open")
    app.element("set.edit.reps.minus").tap()
    XCTAssertTrue(wait(reps, "8"), reps.label)
    app.element("set.edit.save").tap()
    XCTAssertTrue(wait(chip, "65 x 8"), chip.label)
    saveScreenshot("s055-day-sets", of: app)
  }

  @MainActor
  private func tap(_ id: String, in app: XCUIApplication, up: Bool = true) {
    let element = app.element(id)
    XCTAssertTrue(element.waitForExistence(timeout: 10), "no \(id)")
    for _ in 0..<3 where !element.isHittable {
      if up { app.swipeUp() } else { app.swipeDown() }
    }
    element.tap()
  }

  @MainActor
  private func wait(_ element: XCUIElement, _ label: String) -> Bool {
    let match = NSPredicate(format: "label == %@", label)
    return XCTWaiter().wait(for: [expectation(for: match, evaluatedWith: element)], timeout: 10)
      == .completed
  }
}
