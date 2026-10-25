import XCTest

/// S-001: open an area from Home, switch areas with the bottom circles, and go back Home.
final class ShellNavigationUITests: XCTestCase {
  @MainActor
  func testBottomCirclesSwitchAreas() {
    continueAfterFailure = false
    let app = UITestApp.launch()

    // Step 1: three cards, each with a label, a subtitle and "--" for its missing number.
    for (area, label) in [("data", "Data"), ("food", "Food"), ("workout", "Workout")] {
      let card = app.element("home.card.\(area)")
      XCTAssertTrue(card.waitForExistence(timeout: 30), "no \(area) card on Home")
      let text = card.label + " " + ((card.value as? String) ?? "")
      XCTAssertTrue(text.contains(label), "the \(area) card has no label: \(text)")
      XCTAssertTrue(text.contains("--"), "the \(area) card does not show --: \(text)")
    }
    saveScreenshot("s001-home", of: app)

    // Step 2: one tap into Workout; the bottom nav shows three circles, Workout black.
    app.element("home.card.workout").tap()
    XCTAssertTrue(app.element("screen.workout.title").waitForExistence(timeout: 10))
    assertActiveCircle("workout", in: app)
    saveScreenshot("s001-workout", of: app)

    // Step 3: one tap per area switch.
    for (area, shot) in [("food", "s001-food"), ("data", "s001-data")] {
      app.element("nav.circle.\(area)").tap()
      XCTAssertTrue(
        app.element("screen.\(area).title").waitForExistence(timeout: 10),
        "the \(area) screen did not open")
      assertActiveCircle(area, in: app)
      saveScreenshot(shot, of: app)
    }

    // Step 4: one tap back Home.
    app.element("nav.home").tap()
    XCTAssertTrue(
      app.element("home.card.data").waitForExistence(timeout: 10), "Home did not come back")
    XCTAssertFalse(app.element("nav.circle.data").exists, "the bottom nav stayed on Home")
  }

  @MainActor
  private func assertActiveCircle(_ active: String, in app: XCUIApplication) {
    for area in ["data", "food", "workout"] {
      let circle = app.element("nav.circle.\(area)")
      XCTAssertTrue(circle.waitForExistence(timeout: 10), "no \(area) circle")
      XCTAssertEqual(
        circle.value as? String, area == active ? "active" : "inactive",
        "the \(area) circle is in the wrong state")
    }
  }
}
