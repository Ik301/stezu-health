import XCTest

/// S-002: open Settings from the Home gear, save a server address and token, and test the
/// connection. The fake transport answers GET /health; the address and token are synthetic.
final class ServerSettingsUITests: XCTestCase {
  @MainActor
  func testSaveServerAndTestConnection() {
    continueAfterFailure = false
    let app = UITestApp.launch()

    // Step 1: one tap on the gear; both fields are empty and no token is saved.
    let gear = app.element("home.settings")
    XCTAssertTrue(gear.waitForExistence(timeout: 30), "no gear on Home")
    gear.tap()
    XCTAssertTrue(app.element("screen.settings.title").waitForExistence(timeout: 10))
    let address = app.textFields["settings.address"]
    let token = app.secureTextFields["settings.token"]
    XCTAssertTrue(address.waitForExistence(timeout: 10), "no Server address field")
    XCTAssertTrue(token.exists, "no Token field")
    XCTAssertTrue(
      ["", "Server address"].contains((address.value as? String) ?? ""),
      "the address is not empty: \(String(describing: address.value))")
    XCTAssertTrue(
      ["", "Token"].contains((token.value as? String) ?? ""),
      "the token is not empty: \(String(describing: token.value))")
    XCTAssertEqual(app.element("settings.token.saved").label, "--")
    saveScreenshot("s002-settings-empty", of: app)

    // Step 2: type both and Save; the token shows masked.
    address.tap()
    address.typeText("https://vm.example")
    token.tap()
    token.typeText("synthetic-token\n")
    app.element("settings.save").tap()
    let saved = app.element("settings.token.saved")
    XCTAssertTrue(
      wait(for: saved, label: "••••••••"), "the token is not masked: \(saved.label)")
    XCTAssertFalse(app.staticTexts["synthetic-token"].exists, "the token shows in clear")

    // Step 3: Test connection reaches the fake GET /health.
    app.element("settings.test").tap()
    let status = app.element("settings.status")
    XCTAssertTrue(wait(for: status, label: "Connected"), "status is \(status.label)")
    saveScreenshot("s002-settings-connected", of: app)
  }

  @MainActor
  private func wait(for element: XCUIElement, label: String) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label == %@", label), object: element)
    return XCTWaiter().wait(for: [expectation], timeout: 10) == .completed
  }
}
