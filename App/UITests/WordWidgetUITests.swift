import XCTest

/// S-060: the Word widget shows today's word and its definition, keeps the last good copy
/// offline with a "Saved" line, and shows "--" when the vault has no word. The gallery draws the
/// widget's own view at small and medium size from the fake server; the word is made up.
final class WordWidgetUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testWordWidgetLiveOfflineAndMissing() {
    // Live: the fake server's word and its (long) definition, in both sizes.
    var app = UITestApp.launch(reset: true, widgets: true)
    let word = app.staticTexts.matching(identifier: "widget.word.word")
    XCTAssertTrue(word.firstMatch.waitForExistence(timeout: 10))
    XCTAssertEqual(word.count, 2)
    XCTAssertEqual(word.firstMatch.label, "Florble")
    let definition = app.staticTexts.matching(identifier: "widget.word.definition").firstMatch
    XCTAssertTrue(definition.label.hasPrefix("the small sound a kettle makes"))
    XCTAssertFalse(app.element("widget.saved").exists)
    saveScreenshot("s060-word-live", of: app)

    // Offline: the copy saved by the live launch, marked with its day, since it isn't today's.
    app.terminate()
    app = UITestApp.launch(offline: true, widgets: true)
    XCTAssertTrue(app.staticTexts["widget.word.word"].firstMatch.waitForExistence(timeout: 10))
    XCTAssertEqual(app.staticTexts["widget.word.word"].firstMatch.label, "Florble")
    XCTAssertEqual(app.staticTexts["widget.saved"].firstMatch.label, "Saved 2026-03-11")
    saveScreenshot("s060-word-offline", of: app)

    // Missing: the vault has no word, so both fields show "--", never a made-up value.
    app.terminate()
    app = UITestApp.launch(scenario: "surface-missing", reset: true, widgets: true)
    XCTAssertTrue(app.staticTexts["widget.word.word"].firstMatch.waitForExistence(timeout: 10))
    XCTAssertEqual(app.staticTexts["widget.word.word"].firstMatch.label, "--")
    XCTAssertEqual(app.staticTexts["widget.word.definition"].firstMatch.label, "--")
    XCTAssertFalse(app.element("widget.saved").exists)
    saveScreenshot("s060-word-missing", of: app)
  }
}
