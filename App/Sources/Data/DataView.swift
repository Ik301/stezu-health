import StezuCore
import SwiftUI

/// The Data area's root screen. The first open explains what Stezu reads and writes with one
/// Connect button (S-020); once Health has asked, Data opens to the overview. Keep the
/// "screen.data.title" id on its title so the smoke UI test still finds it.
struct DataView: View {
  var goHome: () -> Void = {}
  @Environment(\.appEnvironment) private var environment
  @State private var connected: Bool?
  @State private var sourcesOpen = false

  var body: some View {
    AreaScaffold(area: .data, title: "This week", goHome: goHome) {
      if connected ?? environment.healthConnection.isConnected {
        WeightRow()
        pill("Sources", id: "data.sources", inverted: false) { sourcesOpen = true }
      } else {
        Text(
          "Stezu reads weight, steps, heart rate, HRV, resting heart rate, sleep, food and "
            + "workouts to show your week. It writes weigh-ins, meals and strength workouts so "
            + "they sit in Health with everything else. Health asks once, for all of them."
        )
        .font(.system(size: Theme.subtitleSize)).foregroundStyle(Theme.text)
        pill("Connect Apple Health", id: "data.connect", inverted: true) {
          Task {
            let health = environment.healthConnection
            connected = (try? await health.connect(to: environment.healthStore)) != nil
          }
        }
      }
    }
    .sheet(isPresented: $sourcesOpen) {
      SourcesView(store: environment.healthStore).presentationDragIndicator(.visible)
    }
  }

  private func pill(_ title: String, id: String, inverted: Bool, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Text(title).font(.system(size: 17, weight: .semibold))
        .foregroundStyle(inverted ? Theme.invertedText : Theme.text)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(inverted ? Theme.invertedCard : Color.white, in: Capsule())
    }
    .accessibilityIdentifier(id)
  }
}

#Preview {
  DataView()
}
