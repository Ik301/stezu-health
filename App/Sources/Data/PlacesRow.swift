import StezuCore
import SwiftUI

/// S-032: this week's visits and days with location data, or "--". No map, no inferred places.
struct PlacesRow: View {
  @Environment(\.appEnvironment) private var environment
  @State private var places: PlacesWeek?

  var body: some View {
    HStack {
      Text("Places").textStyle(.headline)
      Spacer()
      Text(places.map { "\($0.visits) visits, \($0.daysWithData) of 7 days" } ?? "--")
        .textStyle(.value).accessibilityIdentifier("data.places.value")
    }
    .foregroundStyle(Theme.ink)
    .padding(Theme.spaceLg)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    .task {
      places = await environment.places.log.week(WeeklyStats.week(containing: environment.now()))
    }
  }
}
