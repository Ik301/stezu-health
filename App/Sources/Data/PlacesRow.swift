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
/// S-053: his own places (D-133) name every visit inside them first; a long press on the full
/// map, or "New place here" on a spot, draws one in the same sheet.
struct PlacesView: View {
  @Environment(\.appEnvironment) private var environment
  @Environment(\.dismiss) private var dismiss
  @State private var log: LocationLog?
  @State private var visits: [PlaceRecord]?
  @State private var names: [String: String] = [:]
  /// The visits within 100 m of the last tap, nearest first; nil before a tap.
  @State private var spot: [PlaceRecord]?
  @State private var full = false
  @State private var mine = MyPlaces()
  @State private var draft: MyPlace?  // the place being drawn or edited

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
            Text(mine.name(visit, looked: names) ?? "Unnamed place").textStyle(.headline)
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
          action: .init(title: "Done", id: "places.map.done") {
            (spot, draft, full) = (nil, nil, false)
          }
        )
        .padding(.horizontal, Theme.spaceLg)
        PlacesMap(
          places: log?.places ?? [], full: true, mine: mine, draft: draft, pressed: start,
          edit: { (spot, draft) = (nil, $0) }, tapped: { if draft == nil { pick($0, $1) } }
        )
        .ignoresSafeArea(edges: .bottom).mapControls { MapUserLocationButton() }
      }
      .foregroundStyle(Theme.ink).background(Theme.ground)
      .sheet(
        isPresented: Binding(
          get: { spot != nil || draft != nil }, set: { if !$0 { (spot, draft) = (nil, nil) } })
      ) {
        Group {
          if let draft {
            PlaceEditor(
              // A field ending its edit after Save or Delete must not reopen the place.
              place: Binding(get: { draft }, set: { if self.draft != nil { self.draft = $0 } }),
              isNew: !mine.places.contains { $0.id == draft.id },
              inside: inside(draft)
            ) { delete in
              self.draft = nil
              Task { mine = await environment.myPlaces.set(draft, delete: delete) }
            }
          } else if let spot {
            card(spot)
          }
        }
        .presentationDetents([.medium]).presentationBackgroundInteraction(.enabled)
      }
    }
  }

  private func card(_ spot: [PlaceRecord]) -> some View {
    let place = spot.first.flatMap(mine.place(for:))
    return PlaceSpotCard(
      visits: spot, name: spot.first.flatMap { mine.name($0, looked: names) }, mine: place,
      place: {
        if let place {
          (self.spot, draft) = (nil, place)
        } else if let at = spot.first {
          start(at.latitude, at.longitude)
        }
        full = true
      },
      save: { label in
        Task { names = await environment.placeNames.label(label, visits: spot.map(\.id)) }
      })
  }

  private func inside(_ place: MyPlace) -> Int {
    log?.visits(near: place.latitude, place.longitude, within: place.radiusM).count ?? 0
  }

  /// A new place centred there (S-053), 75 m across by default; while one is being drawn, a
  /// long press moves it instead.
  private func start(_ latitude: Double, _ longitude: Double) {
    var place = draft ?? MyPlace(id: UUID().uuidString, name: "", latitude: 0, longitude: 0)
    (place.latitude, place.longitude) = (latitude, longitude)
    (spot, draft) = (nil, place)
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
    mine = await environment.myPlaces.places
    // D-119: looked up only while the app is open, once a visit; the names stay on the phone.
    if UIApplication.shared.applicationState == .active {
      names = await environment.placeNames.name(found)
    }
  }
}
