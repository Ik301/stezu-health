import MapKit
import StezuCore
import SwiftUI

/// Places' heat map (native MapKit): every visit is a faint circle as large as its accuracy, and
/// every location fix a fainter 10 m dot, so the spots Isaac goes back to stack up darker
/// (S-052). On Places it is a still preview; full screen, pinch, pan and rotate all work and it
/// opens on the newest visit. A tap passes the coordinate under the finger on.
struct PlacesMap: View {
  let places: [PlaceRecord]
  var full = false
  let tapped: (_ latitude: Double, _ longitude: Double) -> Void

  var body: some View {
    MapReader { proxy in
      Map(initialPosition: full ? start : .automatic, interactionModes: full ? .all : []) {
        ForEach(places, id: \.id) { place in
          MapCircle(
            center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
            radius: place.mapRadius
          )
          .foregroundStyle(Theme.dataEnergyBand.opacity(place.at == nil ? 1 : 0.5))
        }
        UserAnnotation()
      }
      .onTapGesture { point in
        if let spot = proxy.convert(point, from: .local) { tapped(spot.latitude, spot.longitude) }
      }
    }
    .frame(height: full ? nil : 280).clipShape(
      RoundedRectangle(cornerRadius: full ? 0 : Theme.radiusCard)
    )
    .accessibilityIdentifier(full ? "places.map.full" : "places.map")
  }

  /// About 1 km around the newest visit, where the circles are drawn to scale; else all of it.
  private var start: MapCameraPosition {
    let visits = places.filter { $0.at == nil }
    guard
      let newest = visits.max(by: {
        ($0.times.first ?? .distantPast) < ($1.times.first ?? .distantPast)
      })
    else { return .automatic }
    let center = CLLocationCoordinate2D(latitude: newest.latitude, longitude: newest.longitude)
    return .region(
      MKCoordinateRegion(center: center, latitudinalMeters: 1000, longitudinalMeters: 1000))
  }
}

/// The tapped spot: its label (or "No label"), how many visits it holds, and a field to add or
/// change the label. Save names every visit at the spot, on the phone only (D-119).
struct PlaceSpotCard: View {
  let visits: [PlaceRecord]
  let name: String?
  let save: (String) -> Void
  @State private var label = ""

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spaceSm) {
      if visits.isEmpty {
        Text("No visit here").textStyle(.subtitle).accessibilityIdentifier("places.spot.none")
      } else {
        Text(name ?? "No label").textStyle(.headline).accessibilityIdentifier("places.spot.name")
        Text("\(visits.count) visit\(visits.count == 1 ? "" : "s")").textStyle(.label)
          .foregroundStyle(Theme.muted)
        HStack(spacing: Theme.spaceSm) {
          TextField("Label", text: $label).textStyle(.subtitle)
            .padding(.horizontal, Theme.spaceMd).frame(minHeight: Theme.sizeTarget)
            .background(Theme.surfaceRaised, in: Capsule())
            .accessibilityIdentifier("places.spot.field")
          Button("Save") { save(label) }.textStyle(.headline)
            .frame(minHeight: Theme.sizeTarget).accessibilityIdentifier("places.spot.save")
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(Theme.spaceCard)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    .onAppear { label = name ?? "" }
    .onChange(of: visits.first?.id) { label = name ?? "" }
  }
}
