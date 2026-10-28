import XCTest

/// S-040: the Sleep row opens the Sleep screen (design/system/walkthroughs/data.html). With the
/// home-week scenario (Sunday clock; synthetic nights ending Mon, Tue, Wed, Fri, Sat and Sun,
/// none on Thursday) the top shows last night and the usual night, the window has 14 nights with
/// "--" for each one without data, last night's stages and wake-ups follow, and tapping
/// Saturday switches the top number and the wake-ups to Saturday's. All numbers are made up.
final class SleepDetailUITests: XCTestCase {
  @MainActor
  func testSleepScreenWindowAndNightSelection() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "home-week")
    openSleep(app)

    // Step 2: last night's time asleep and the usual night, descriptive only.
    XCTAssertEqual(app.element("sleep.title").label, "Sleep")
    XCTAssertEqual(app.element("sleep.night").label, "Last night")
    XCTAssertEqual(app.element("sleep.usual").label, "Usual 7h 20m, your median of 6 nights")

    // Step 3: 14 nights in the window, Monday December 29 to Sunday January 11. Thursday the 8th
    // (index 10) has no data: "--" and nothing to tap.
    let values = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier MATCHES %@", "sleep\\.window\\.[0-9]+\\.value"))
    XCTAssertEqual(values.count, 14, "not 14 nights in the window")
    XCTAssertEqual(app.element("sleep.window.10.value").label, "--")
    XCTAssertFalse(app.element("sleep.window.10").exists, "a night without data is tappable")
    XCTAssertEqual(app.element("sleep.window.12.value").label, "7h 20m")
    XCTAssertEqual(app.element("sleep.window.13.value").label, "6h 15m")
    XCTAssertTrue(app.staticTexts["6 of 14 nights"].exists)

    // Step 4: last night's stages, labelled as the strap's estimate, and its wake-ups.
    XCTAssertTrue(app.element("sleep.stages").exists, "no hypnogram")
    XCTAssertTrue(app.staticTexts["Estimated by the strap"].exists)
    XCTAssertEqual(
      app.element("sleep.wakeups").label, "2 wake-ups, 15m awake after falling asleep")
    saveScreenshot("s040-sleep-light", of: app)

    // Steps 3 and 7: tapping Saturday switches the top number and the wake-ups.
    app.element("sleep.window.12").tap()
    XCTAssertTrue(waitForLabel(app.element("sleep.asleep"), "7h 20m"), "Saturday not picked")
    XCTAssertTrue(app.element("sleep.night").label.hasPrefix("Saturday"))
    XCTAssertEqual(
      app.element("sleep.wakeups").label, "1 wake-up, 10m awake after falling asleep")

    // Step 6: the footer.
    let footer = app.element("sleep.footer")
    for _ in 0..<3 where !footer.isHittable { app.swipeUp() }
    XCTAssertEqual(
      footer.label,
      "Nights are named by the morning you woke up. Tracking only: no score, no target.")

    // Dark follows the phone.
    app.terminate()
    let dark = UITestApp.launch(scenario: "home-week", dark: true)
    openSleep(dark)
    saveScreenshot("s040-sleep-dark", of: dark)
  }

  /// Home, Data, then the Sleep row (1 tap from This week); waits for last night.
  @MainActor
  private func openSleep(_ app: XCUIApplication) {
    let card = app.element("home.card.data")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Data card on Home")
    card.tap()
    let row = app.element("data.sleep.open")
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no Sleep row")
    for _ in 0..<3 where !row.isHittable { app.swipeUp() }
    row.tap()
    XCTAssertTrue(waitForLabel(app.element("sleep.asleep"), "6h 15m"), "Sleep did not open")
  }

  @MainActor
  private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
    let match = NSPredicate(format: "label == %@", label)
    return XCTWaiter().wait(for: [expectation(for: match, evaluatedWith: element)], timeout: 10)
      == .completed
  }
}
