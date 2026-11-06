import XCTest

/// S-061: the Goal widget shows the current goals, keeps the last good copy offline with a
/// "Saved" line, and shows "--" when the vault has no goals. The gallery draws the widget's own
/// view at small and medium size from the fake server; the goals are made up.
final class GoalWidgetUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testGoalWidgetLiveOfflineAndMissing() {
    // Live: three goals in each size.
    var app = UITestApp.launch(reset: true, widgets: true)
    let lines = app.staticTexts.matching(identifier: "widget.goal.line")
    XCTAssertTrue(lines.firstMatch.waitForExistence(timeout: 10))
    XCTAssertEqual(lines.count, 6)
    XCTAssertEqual(
      (0..<3).map { lines.element(boundBy: $0).label },
      [
        "Learn to juggle three balls", "Paint the garden gate blue",
        "Walk the long loop every Sunday",
      ])
    XCTAssertFalse(app.element("widget.saved").exists)
    saveScreenshot("s061-goal-live", of: app)

    // Offline: the goals saved by the live launch, marked with their day.
    app.terminate()
    app = UITestApp.launch(offline: true, widgets: true)
    let cached = app.staticTexts.matching(identifier: "widget.goal.line")
    XCTAssertTrue(cached.firstMatch.waitForExistence(timeout: 10))
    XCTAssertEqual(cached.firstMatch.label, "Learn to juggle three balls")
    XCTAssertEqual(app.staticTexts["widget.saved"].firstMatch.label, "Saved 2026-03-11")
    saveScreenshot("s061-goal-offline", of: app)

    // Missing: no goals in the vault, so one "--" per widget.
    app.terminate()
    app = UITestApp.launch(scenario: "surface-missing", reset: true, widgets: true)
    let missing = app.staticTexts.matching(identifier: "widget.goal.line")
    XCTAssertTrue(missing.firstMatch.waitForExistence(timeout: 10))
    XCTAssertEqual(missing.count, 2)
    XCTAssertEqual(missing.firstMatch.label, "--")
    saveScreenshot("s061-goal-missing", of: app)
  }
}
