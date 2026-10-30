import MapKit
import StezuCore
import SwiftUI

/// Places' heat map (native MapKit): every visit and location fix in the phone's log is a faint
/// circle, so the spots Isaac goes back to stack up darker. A tap passes the coordinate under
/// the finger on; Places finds the visits there.
struct PlacesMap: View {
  let places: [PlaceRecord]
  let tapped: (_ latitude: Double, _ longitude: Double) -> Void

  var body: some View {
    MapReader { proxy in
      Map(initialPosition: .automatic) {
        ForEach(places, id: \.id) { place in
          MapCircle(
            center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
            radius: 80
          )
          .foregroundStyle(Theme.dataEnergyBand)
        }
      }
      .onTapGesture { point in
        if let spot = proxy.convert(point, from: .local) { tapped(spot.latitude, spot.longitude) }
      }
    }
    .frame(height: 280).clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard))
    .accessibilityIdentifier("places.map")
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
