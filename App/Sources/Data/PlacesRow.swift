import StezuCore
import SwiftUI
import UIKit

/// S-032, S-048: this week's visits as a MetricRow under a Places header, with the days with
/// location data and a bar Sparkline of visits per day; "--" without data. A tap opens the
/// week's visits, newest first, each with its name and times. No inferred places.
struct PlacesRow: View {
  @Environment(\.appEnvironment) private var environment
  @State private var places: PlacesWeek?
  @State private var open = false

  var body: some View {
    MetricCard(title: "Places") {
      MetricRow(
        title: "Visits", id: "places",
        coverage: places.map { "\($0.daysWithData) of 7 days" } ?? "--",
        values: places?.perDay ?? [], value: places.map { "\($0.visits)" } ?? "--", first: true
      ) { open = true }
    }
    .task {
      places = await environment.places.log.week(WeeklyStats.week(containing: environment.now()))
    }
    .sheet(isPresented: $open) { PlacesView().presentationDragIndicator(.visible) }
  }
}

/// Where Isaac has been this week: each visit from the phone's location log, newest first, with
/// its name (Apple's geocoder, kept on the phone, D-119) or "Unnamed place", and its times.
struct PlacesView: View {
  @Environment(\.appEnvironment) private var environment
  @Environment(\.dismiss) private var dismiss
  @State private var visits: [PlaceRecord]?
  @State private var names: [String: String] = [:]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.spaceMd) {
        TopBar(
          title: "Places", titleID: "places.title",
          action: .init(title: "Done", id: "places.done") { dismiss() })
        if visits?.isEmpty == true { Text("--").accessibilityIdentifier("places.empty") }
        ForEach(Array((visits ?? []).enumerated()), id: \.element.id) { index, visit in
          VStack(alignment: .leading, spacing: Theme.space2xs) {
            Text(names[visit.id] ?? "Unnamed place").textStyle(.headline)
              .accessibilityIdentifier("places.visit.\(index).name")
            Text(Self.times(visit)).textStyle(.label).foregroundStyle(Theme.muted)
          }
          .frame(maxWidth: .infinity, alignment: .leading).padding(Theme.spaceCard)
          .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("places.visit.\(index)")
        }
      }
      .padding(Theme.spaceLg)
    }
    .foregroundStyle(Theme.ink).background(Theme.ground)
    .task { await load() }
  }

  /// "Mon 12:10 PM to 5:50 PM", or one time while the departure is unknown.
  static func times(_ visit: PlaceRecord) -> String {
    let times = visit.times
    guard let from = times.first else { return "--" }
    let start = from.formatted(.dateTime.weekday().hour().minute())
    guard let to = times.last, times.count > 1 else { return start }
    return "\(start) to \(to.formatted(date: .omitted, time: .shortened))"
  }

  private func load() async {
    let week = WeeklyStats.week(containing: environment.now())
    let found = await environment.places.log.places.filter { place in
      place.at == nil && place.times.first.map(week.contains) == true
    }
    visits = found.sorted { ($0.times.first ?? .distantPast) > ($1.times.first ?? .distantPast) }
    names = await environment.placeNames.names
    // D-119: looked up only while the app is open, once a visit; the names stay on the phone.
    if UIApplication.shared.applicationState == .active {
      names = await environment.placeNames.name(found)
    }
  }
}
