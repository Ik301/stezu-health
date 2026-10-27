import XCTest

/// The smoke walk in the dark appearance (`-uitest-dark`): Home and each area, one screenshot
/// each, so the Dark tokens can be checked by eye.
final class DarkSmokeUITests: XCTestCase {
  @MainActor
  func testDarkAppearanceShowsHomeAndEachArea() {
    continueAfterFailure = false
    let app = UITestApp.launch(dark: true)
    for area in ["data", "food", "workout"] {
      XCTAssertTrue(
        app.element("home.card.\(area)").waitForExistence(timeout: 30), "no \(area) card on Home")
    }
    saveScreenshot("smoke-home-dark", of: app)

    for (area, title) in [("data", "This week"), ("food", "Food"), ("workout", "Workout")] {
      app.element("home.card.\(area)").tap()
      let heading = app.element("screen.\(area).title")
      XCTAssertTrue(heading.waitForExistence(timeout: 10), "the \(area) screen did not open")
      XCTAssertEqual(heading.label, title)
      saveScreenshot("smoke-\(area)-dark", of: app)
      app.element("nav.home").tap()
      XCTAssertTrue(
        app.element("home.card.\(area)").waitForExistence(timeout: 10), "Home did not come back")
    }
  }
}
