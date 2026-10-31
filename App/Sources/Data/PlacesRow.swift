import MapKit
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

/// Where Isaac has been: a heat map of the whole location log, then this week's visits, newest
/// first, with each name (Apple's geocoder or his label, kept on the phone, D-119) or "Unnamed
/// place", and its times. A tap on a visit opens that spot's label (D-130); a tap on the map, or
/// its Expand button, opens the map full screen, where a tap on a spot opens its label as a sheet.
struct PlacesView: View {
  @Environment(\.appEnvironment) private var environment
  @Environment(\.dismiss) private var dismiss
  @State private var log: LocationLog?
  @State private var visits: [PlaceRecord]?
  @State private var names: [String: String] = [:]
  /// The visits within 100 m of the last tap, nearest first; nil before a tap.
  @State private var spot: [PlaceRecord]?
  @State private var full = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.spaceMd) {
        TopBar(
          title: "Places", titleID: "places.title",
          action: .init(title: "Done", id: "places.done") { dismiss() })
        if let log, !log.places.isEmpty {
          PlacesMap(places: log.places) { _, _ in expand() }
            .overlay(alignment: .topTrailing) {
              Button(action: expand) {
                Image(systemName: "arrow.up.left.and.arrow.down.right").textStyle(.headline)
                  .frame(width: Theme.sizeTarget, height: Theme.sizeTarget)
                  .background(Theme.surface, in: Circle())
              }
              .padding(Theme.spaceSm).accessibilityLabel("Expand map")
              .accessibilityIdentifier("places.map.expand")
            }
        }
        if let spot { card(spot) }
        if visits?.isEmpty == true { Text("--").accessibilityIdentifier("places.empty") }
        ForEach(Array((visits ?? []).enumerated()), id: \.element.id) { index, visit in
          VStack(alignment: .leading, spacing: Theme.space2xs) {
            Text(names[visit.id] ?? "Unnamed place").textStyle(.headline)
              .accessibilityIdentifier("places.visit.\(index).name")
            Text(Self.times(visit)).textStyle(.label).foregroundStyle(Theme.muted)
          }
          .frame(maxWidth: .infinity, alignment: .leading).padding(Theme.spaceCard)
          .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
          .contentShape(Rectangle()).onTapGesture { pick(visit.latitude, visit.longitude) }
          .accessibilityElement(children: .contain).accessibilityAddTraits(.isButton)
          .accessibilityIdentifier("places.visit.\(index)")
        }
      }
      .padding(Theme.spaceLg)
    }
    .foregroundStyle(Theme.ink).background(Theme.ground)
    .task { await load() }
    .fullScreenCover(isPresented: $full) {
      VStack(spacing: 0) {
        TopBar(
          title: "Places", titleID: "places.map.title",
          action: .init(title: "Done", id: "places.map.done") { (spot, full) = (nil, false) }
        )
        .padding(.horizontal, Theme.spaceLg)
        PlacesMap(places: log?.places ?? [], full: true) { pick($0, $1) }
          .ignoresSafeArea(edges: .bottom).mapControls { MapUserLocationButton() }
      }
      .foregroundStyle(Theme.ink).background(Theme.ground)
      .sheet(isPresented: Binding(get: { spot != nil }, set: { if !$0 { spot = nil } })) {
        if let spot {
          card(spot).presentationDetents([.medium]).presentationBackgroundInteraction(.enabled)
        }
      }
    }
  }

  private func card(_ spot: [PlaceRecord]) -> some View {
    PlaceSpotCard(visits: spot, name: spot.first.flatMap { names[$0.id] }) { label in
      Task { names = await environment.placeNames.label(label, visits: spot.map(\.id)) }
    }
  }

  /// The map full screen (S-052), with no spot open yet.
  private func expand() { (spot, full) = (nil, true) }

  /// "Mon 12:10 PM to 5:50 PM", or one time while the departure is unknown.
  static func times(_ visit: PlaceRecord) -> String {
    let times = visit.times
    guard let from = times.first else { return "--" }
    let start = from.formatted(.dateTime.weekday().hour().minute())
    guard let to = times.last, times.count > 1 else { return start }
    return "\(start) to \(to.formatted(date: .omitted, time: .shortened))"
  }

  private func pick(_ latitude: Double, _ longitude: Double) {
    spot = log?.visits(near: latitude, longitude, within: 100)
  }

  private func load() async {
    let week = WeeklyStats.week(containing: environment.now())
    log = await environment.places.log
    let found = (log?.places ?? []).filter { place in
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
