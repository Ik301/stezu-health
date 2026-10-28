import StezuCore
import SwiftUI

/// S-032, S-048: this week's visits as a MetricRow under a Places header, with the days with
/// location data and a bar Sparkline of visits per day; "--" without data. No map, no inferred
/// places, and no detail yet, so no chevron.
struct PlacesRow: View {
  @Environment(\.appEnvironment) private var environment
  @State private var places: PlacesWeek?

  var body: some View {
    MetricCard(title: "Places") {
      MetricRow(
        title: "Visits", id: "places",
        coverage: places.map { "\($0.daysWithData) of 7 days" } ?? "--",
        values: places?.perDay ?? [], value: places.map { "\($0.visits)" } ?? "--", first: true)
    }
    .task {
      places = await environment.places.log.week(WeeklyStats.week(containing: environment.now()))
    }
  }
}
