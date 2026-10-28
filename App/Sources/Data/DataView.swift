import StezuCore
import SwiftUI

/// The Data area's root screen. The first open explains what Ingest reads and writes with one
/// Connect button (S-020); once Health has asked, Data opens to the overview. Keep the
/// "screen.data.title" id on its title so the smoke UI test still finds it.
struct DataView: View {
  var goHome: () -> Void = {}
  @Environment(\.appEnvironment) private var environment
  @State private var connected: Bool?
  @State private var sourcesOpen = false
  @State private var notInHealth: [String] = []
  @State private var metric: Metric?

  var body: some View {
    let isConnected = connected ?? environment.healthConnection.isConnected
    AreaScaffold(area: .data, title: "This week", goHome: goHome) {
      if isConnected {
        ScrollView {
          VStack(spacing: Theme.spaceMd) {
            BodyCard { metric = $0 }
            MetricCard(title: "Food and training") { WeeklyFoodWorkoutRows { metric = $0 } }
            MetricCard(title: "Recovery", tag: "context only") {
              WeeklyHealthRows(metrics: [.sleep, .hrv, .restingHR, .breathing], hint: true) {
                metric = $0
              }
            }
            PlacesRow()
            Button("Sources", action: sources).textStyle(.subtitle).foregroundStyle(Theme.muted)
              .buttonStyle(.plain)
              .frame(maxWidth: .infinity, minHeight: Theme.sizeTarget, alignment: .leading)
              .padding(.horizontal, Theme.spaceLg).accessibilityIdentifier("data.sources")
          }
        }
        .scrollIndicators(.hidden)
      } else {
        Text(
          "Ingest reads weight, steps, heart rate, HRV, resting heart rate, sleep, blood oxygen, "
            + "respiratory rate, temperature, food and workouts to show your week. It writes "
            + "weigh-ins, meals and strength workouts so they sit in Health with everything else. "
            + "Health asks once, for all of them."
        )
        .textStyle(.subtitle).foregroundStyle(Theme.ink)
        pill("Connect Apple Health", id: "data.connect", inverted: true) {
          Task {
            let health = environment.healthConnection
            connected = (try? await health.connect(to: environment.healthStore)) != nil
          }
        }
      }
    }
    .sheet(isPresented: $sourcesOpen) { [notInHealth] in
      SourcesView(store: environment.healthStore, failedWrites: notInHealth, now: environment.now())
        .presentationDragIndicator(.visible)
    }
    .sheet(item: $metric) { MetricDetailView(metric: $0).presentationDragIndicator(.visible) }
  }

  private func sources() {
    Task { (notInHealth, sourcesOpen) = (await environment.weighInsNotInHealth(), true) }
  }

  private func pill(_ title: String, id: String, inverted: Bool, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Text(title).textStyle(.headline)
        .foregroundStyle(inverted ? Theme.onInvert : Theme.ink)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(inverted ? Theme.invert : Theme.surfaceRaised, in: Capsule())
    }
    .accessibilityIdentifier(id)
  }
}

#Preview {
  DataView()
}
