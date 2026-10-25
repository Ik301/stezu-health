import XCTest

/// Launches the app for a UI test with the `-uitest` fakes: an in-memory store, FakeHealthStore,
/// FakeVMTransport and the fixture photo. Scenarios seed synthetic data only (D-034).
enum UITestApp {
  @MainActor
  static func launch(
    scenario: String? = nil, offline: Bool = false, persist: Bool = false, reset: Bool = false
  ) -> XCUIApplication {
    var arguments = ["-uitest"]
    if let scenario { arguments += ["-uitest-scenario", scenario] }
    if offline { arguments.append("-uitest-offline") }
    if persist { arguments.append("-uitest-persist") }
    if reset { arguments.append("-uitest-reset") }
    let app = XCUIApplication()
    app.launchArguments = arguments
    app.launch()
    return app
  }
}

extension XCUIApplication {
  /// The element with this accessibility identifier, whatever its type.
  @MainActor
  func element(_ identifier: String) -> XCUIElement {
    descendants(matching: .any).matching(identifier: identifier).firstMatch
  }
}

extension XCTestCase {
  /// Attaches a screenshot named `name` and keeps it when the test passes. CI exports it under
  /// that name, and features.json lists each story's screenshot names.
  @MainActor
  func saveScreenshot(_ name: String, of app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
