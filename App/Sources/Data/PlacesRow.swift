import StezuCore
import SwiftUI

/// S-032: this week's visits and days with location data, or "--". No map, no inferred places.
struct PlacesRow: View {
  @Environment(\.appEnvironment) private var environment
  @State private var places: PlacesWeek?

  var body: some View {
    HStack {
      Text("Places").font(.system(size: 17, weight: .semibold))
      Spacer()
      Text(places.map { "\($0.visits) visits, \($0.daysWithData) of 7 days" } ?? "--")
        .font(.system(size: 17, weight: .medium)).accessibilityIdentifier("data.places.value")
    }
    .foregroundStyle(Theme.text)
    .padding(16)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    .task {
      places = await environment.places.log.week(WeeklyStats.week(containing: environment.now()))
    }
  }
}
