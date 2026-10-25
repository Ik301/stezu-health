import XCTest

/// Launch, see the three Home cards, open each area and come back.
final class SmokeUITests: XCTestCase {
  @MainActor
  func testLaunchShowsThreeCardsAndEachOpensItsArea() {
    continueAfterFailure = false
    let app = UITestApp.launch()
    for area in ["data", "food", "workout"] {
      XCTAssertTrue(
        app.element("home.card.\(area)").waitForExistence(timeout: 30), "no \(area) card on Home")
    }
    saveScreenshot("smoke-home", of: app)

    for (area, title) in [("data", "This week"), ("food", "Food"), ("workout", "Workout")] {
      app.element("home.card.\(area)").tap()
      let heading = app.element("screen.\(area).title")
      XCTAssertTrue(heading.waitForExistence(timeout: 10), "the \(area) screen did not open")
      XCTAssertEqual(heading.label, title)
      saveScreenshot("smoke-\(area)", of: app)
      app.element("nav.home").tap()
      XCTAssertTrue(
        app.element("home.card.\(area)").waitForExistence(timeout: 10), "Home did not come back")
    }
  }
}
