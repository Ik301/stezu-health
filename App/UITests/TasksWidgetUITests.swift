import XCTest

/// S-062: the Tasks widget lists today's open tasks with Overdue tags and a "+N more" count,
/// keeps the last list offline, says "Nothing due today" when nothing is due, and shows "--" when
/// the tasks are missing. The gallery draws the widget's own view at medium and large size from
/// the fake server; the tasks are made up.
final class TasksWidgetUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testTasksWidgetLiveOfflineEmptyAndMissing() {
    // Live: 14 tasks, the first two overdue. Medium fits 3 and "+11 more", large 11 and "+3 more".
    var app = UITestApp.launch(scenario: "surface-tasks", reset: true, widgets: true)
    let rows = app.staticTexts.matching(identifier: "widget.tasks.row")
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
    XCTAssertEqual(rows.count, 14)
    XCTAssertEqual(rows.firstMatch.label, "Return the library atlas")
    XCTAssertEqual(rows.element(boundBy: 3).label, "Return the library atlas")
    XCTAssertEqual(app.staticTexts.matching(identifier: "widget.tasks.overdue").count, 4)
    let more = app.staticTexts.matching(identifier: "widget.tasks.more")
    XCTAssertEqual(more.count, 2)
    XCTAssertEqual(more.element(boundBy: 0).label, "+11 more")
    XCTAssertEqual(more.element(boundBy: 1).label, "+3 more")
    XCTAssertFalse(app.element("widget.saved").exists)
    saveScreenshot("s062-tasks-live", of: app)

    // Offline: the list saved by the live launch, Overdue tags and all.
    app.terminate()
    app = UITestApp.launch(scenario: "surface-tasks", offline: true, widgets: true)
    let cached = app.staticTexts.matching(identifier: "widget.tasks.row")
    XCTAssertTrue(cached.firstMatch.waitForExistence(timeout: 10))
    XCTAssertEqual(cached.count, 14)
    XCTAssertEqual(cached.firstMatch.label, "Return the library atlas")
    XCTAssertEqual(app.staticTexts.matching(identifier: "widget.tasks.overdue").count, 4)
    XCTAssertEqual(app.staticTexts["widget.tasks.more"].firstMatch.label, "+11 more")
    saveScreenshot("s062-tasks-offline", of: app)

    // Empty: nothing due, so a message instead of rows.
    app.terminate()
    app = UITestApp.launch(scenario: "surface-tasks-empty", reset: true, widgets: true)
    let empty = app.staticTexts.matching(identifier: "widget.tasks.empty")
    XCTAssertTrue(empty.firstMatch.waitForExistence(timeout: 10))
    XCTAssertEqual(empty.count, 2)
    XCTAssertEqual(empty.firstMatch.label, "Nothing due today")
    XCTAssertFalse(app.element("widget.tasks.row").exists)
    saveScreenshot("s062-tasks-empty", of: app)

    // Missing: the server couldn't read the task notes, so "--" and never a made-up list.
    app.terminate()
    app = UITestApp.launch(scenario: "surface-tasks-missing", reset: true, widgets: true)
    let missing = app.staticTexts.matching(identifier: "widget.tasks.missing")
    XCTAssertTrue(missing.firstMatch.waitForExistence(timeout: 10))
    XCTAssertEqual(missing.count, 2)
    XCTAssertEqual(missing.firstMatch.label, "--")
    XCTAssertFalse(app.element("widget.tasks.row").exists)
    saveScreenshot("s062-tasks-missing", of: app)
  }
}
