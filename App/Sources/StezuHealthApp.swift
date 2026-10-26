import SwiftUI
import UIKit

@main
struct StezuHealthApp: App {
  /// `-uitest` swaps in the fakes; see AppEnvironment.
  @State private var environment: AppEnvironment
  @Environment(\.scenePhase) private var scenePhase

  init() {
    let environment = AppEnvironment.fromLaunch()
    _environment = State(initialValue: environment)
    if environment.isUITest {
      UIView.setAnimationsEnabled(false)
    }
  }

  var body: some Scene {
    WindowGroup {
      AppShell(serverSaved: { environment.useServer($0) })
        .environment(\.appEnvironment, environment)
        .onChange(of: scenePhase, initial: true) { _, phase in  // S-028: open and foreground
          if phase == .active { environment.syncHermesInBackground() }
        }
    }
  }
}
