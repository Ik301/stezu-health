import XCTest

/// S-038: every sheet has its TopBar, with Done (or the rung above it) as plain text at the top
/// right, above the title, and Done closes the sheet; swipe down still closes one. Every area
/// screen has Home at the top left. Synthetic data only: data-food-week, workout-history, then
/// food-history.
final class SheetHeaderUITests: XCTestCase {
  @MainActor
  func testEverySheetHasDoneTopRight() {
    continueAfterFailure = false
    var app = UITestApp.launch(scenario: "data-food-week")

    // Settings, from Home: Done, then swipe down.
    let gear = app.element("home.settings")
    XCTAssertTrue(gear.waitForExistence(timeout: 30), "no Settings on Home")
    gear.tap()
    checkDone("settings.done", closes: "screen.settings.title", app)
    gear.tap()
    let settings = app.element("screen.settings.title")
    XCTAssertTrue(settings.waitForExistence(timeout: 10), "Settings did not reopen")
    settings.swipeDown(velocity: .fast)
    XCTAssertTrue(settings.waitForNonExistence(timeout: 10), "swipe down did not close Settings")

    // Data: Sources sits in the TopBar's right slot; Sources, a metric and Weigh in.
    openArea("data", app)
    let sources = app.element("data.sources")
    XCTAssertTrue(sources.waitForExistence(timeout: 10), "no Sources")
    XCTAssertGreaterThan(sources.frame.maxX, width(app) - 40, "Sources is not at the right")
    XCTAssertLessThan(sources.frame.maxY, app.element("screen.data.title").frame.minY + 1)
    sources.tap()
    XCTAssertTrue(app.element("sources.done").waitForExistence(timeout: 10), "Sources did not open")
    saveScreenshot("s038-sources", of: app)
    checkDone("sources.done", closes: "screen.sources.title", app)

    app.element("data.weight.open").tap()
    XCTAssertTrue(app.element("metric.week.0").waitForExistence(timeout: 10), "no weeks")
    saveScreenshot("s038-metric", of: app)
    app.element("metric.week.0").tap()
    checkDone("metric.back", closes: "metric.day.0.name", app)
    checkDone("metric.close", closes: "metric.title", app)

    app.element("data.weighIn").tap()
    checkDone("data.weighIn.done", closes: "data.weighIn.title", app)

    // Workout: History, a session in it, then the Exercises library from the logger. Only the
    // workout-history scenario has past sessions.
    app.terminate()
    app = UITestApp.launch(scenario: "workout-history")
    openArea("workout", app)
    app.element("workout.history").tap()
    let session = app.element("history.session.0.0")
    XCTAssertTrue(session.waitForExistence(timeout: 10), "no session in History")
    saveScreenshot("s038-workout-history", of: app)
    session.tap()
    checkDone("history.session.back", closes: "history.session.title", app)
    checkDone("workout.history.done", closes: "workout.history.title", app)
    let start = app.element("workout.today.start")
    XCTAssertTrue(start.waitForExistence(timeout: 10), "no Start")
    start.tap()
    let menu = app.element("workout.logger.menu")
    XCTAssertTrue(menu.waitForExistence(timeout: 10), "no exercise menu")
    menu.tap()
    let swap = app.element("workout.logger.swap")
    if swap.waitForExistence(timeout: 3) { swap.tap() } else { app.buttons["Swap"].tap() }
    checkDone("workout.library.done", closes: "workout.library.title", app)

    // Food: History and the meal editor from it, then the Matching sheet after the shutter.
    app.terminate()
    app = UITestApp.launch(scenario: "food-history")
    openArea("food", app)
    app.element("food.history").tap()
    let lunch = app.element("food.history.day.0.meal.0.items")
    XCTAssertTrue(lunch.waitForExistence(timeout: 10), "no meal in History")
    saveScreenshot("s038-food-history", of: app)
    lunch.tap()
    checkDone("food.edit.done", closes: "food.match.title", app)
    checkDone("food.history.done", closes: "food.history.title", app)
    let shutter = app.element("food.shutter")
    expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: shutter)
    waitForExpectations(timeout: 10)
    shutter.tap()
    checkDone("food.match.done", closes: "food.matching", app)
  }

  @MainActor
  private func width(_ app: XCUIApplication) -> CGFloat { app.windows.firstMatch.frame.width }

  /// Opens an area from Home and checks Home is at its top left.
  @MainActor
  private func openArea(_ area: String, _ app: XCUIApplication) {
    let card = app.element("home.card.\(area)")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no \(area) card on Home")
    card.tap()
    let home = app.element("nav.home")
    XCTAssertTrue(home.waitForExistence(timeout: 10), "no Home on \(area)")
    XCTAssertTrue(app.element("screen.\(area).title").exists, "no \(area) title")
    XCTAssertLessThan(home.frame.minX, 40, "Home is not at the left on \(area): \(home.frame)")
    XCTAssertLessThan(home.frame.minY, 140, "Home is not at the top on \(area): \(home.frame)")
  }

  /// The sheet's Done (or rung) is hittable, within 40 pt of the right edge and above the
  /// title, and a tap closes what the title belongs to.
  @MainActor
  private func checkDone(
    _ id: String, closes title: String, _ app: XCUIApplication, line: UInt = #line
  ) {
    let done = app.element(id)
    let titled = app.element(title)
    XCTAssertTrue(done.waitForExistence(timeout: 10), "no \(id)", line: line)
    XCTAssertTrue(titled.waitForExistence(timeout: 10), "no \(title)", line: line)
    XCTAssertTrue(done.isHittable, "\(id) is not hittable", line: line)
    XCTAssertGreaterThan(
      done.frame.maxX, width(app) - 40, "\(id) is not at the right: \(done.frame)", line: line)
    if title.hasSuffix("title") || title == "food.matching" {
      XCTAssertLessThan(
        done.frame.midY, titled.frame.minY, "\(id) is not above \(title)", line: line)
    }
    done.tap()
    XCTAssertTrue(titled.waitForNonExistence(timeout: 10), "\(id) did not close", line: line)
  }
}
