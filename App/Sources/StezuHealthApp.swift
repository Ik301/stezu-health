import SwiftUI
import UIKit

@main
struct StezuHealthApp: App {
  /// `-uitest` swaps in the fakes; see AppEnvironment.
  private let environment = AppEnvironment.fromLaunch()

  init() {
    if environment.isUITest {
      UIView.setAnimationsEnabled(false)
    }
  }

  var body: some Scene {
    WindowGroup {
      AppShell()
        .environment(\.appEnvironment, environment)
    }
  }
}
