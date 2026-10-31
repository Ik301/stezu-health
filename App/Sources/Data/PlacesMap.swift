import MapKit
import StezuCore
import SwiftUI

/// Places' heat map (native MapKit): every visit is a faint circle as large as its accuracy, and
/// every location fix a fainter 10 m dot, so the spots Isaac goes back to stack up darker
/// (S-052). On Places it is a still preview; full screen, pinch, pan and rotate all work and it
/// opens on the newest visit. A tap passes the coordinate under the finger on. S-053: his own
/// places are outlined circles with their name (a tap edits one); a long press starts a place
/// there, and the place being drawn colours the visits inside it.
struct PlacesMap: View {
  let places: [PlaceRecord]
  var full = false
  var mine = MyPlaces()
  var draft: MyPlace?
  var pressed: (_ latitude: Double, _ longitude: Double) -> Void = { _, _ in }
  var edit: (MyPlace) -> Void = { _ in }
  let tapped: (_ latitude: Double, _ longitude: Double) -> Void
  @State private var center: CLLocationCoordinate2D?

  var body: some View {
    MapReader { proxy in
      Map(initialPosition: full ? start : .automatic, interactionModes: full ? .all : []) {
        ForEach(places, id: \.id) { place in
          let inside = place.at == nil && draft?.contains(place) == true
          MapCircle(
            center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
            radius: place.mapRadius
          )
          .foregroundStyle(
            (inside ? Theme.dataEnergy : Theme.dataEnergyBand).opacity(place.at == nil ? 1 : 0.5))
        }
        ForEach(mine.places.filter { $0.id != draft?.id } + (draft.map { [$0] } ?? []), id: \.id) {
          place in
          let at = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
          MapCircle(center: at, radius: place.radiusM).foregroundStyle(Theme.track.opacity(0.25))
            .stroke(place.id == draft?.id ? Theme.dataEnergy : Theme.ink, lineWidth: 2)
          Annotation(place.name, coordinate: at) {
            Button(place.name) { edit(place) }.textStyle(.label, weight: .medium)
              .foregroundStyle(Theme.ink).padding(.horizontal, Theme.spaceSm)
              .background(Theme.surface, in: Capsule()).opacity(place.name.isEmpty ? 0 : 1)
          }
        }
        UserAnnotation()
      }
      .annotationTitles(.hidden)
      .onMapCameraChange { center = $0.region.center }
      .onTapGesture { point in
        if let spot = proxy.convert(point, from: .local) { tapped(spot.latitude, spot.longitude) }
      }
      .simultaneousGesture(
        LongPressGesture(minimumDuration: 0.5).sequenced(before: DragGesture(minimumDistance: 0))
          .onEnded { value in
            guard case .second(true, let drag) = value else { return }
            // Without a finger position (no drag event), the place starts at the map's centre.
            if let spot = drag.flatMap({ proxy.convert($0.location, from: .local) }) ?? center
              ?? newest
            {
              pressed(spot.latitude, spot.longitude)
            }
          })
    }
    .frame(height: full ? nil : 280).clipShape(
      RoundedRectangle(cornerRadius: full ? 0 : Theme.radiusCard)
    )
    .accessibilityIdentifier(full ? "places.map.full" : "places.map")
  }

  /// About 1 km around the newest visit, where the circles are drawn to scale; else all of it.
  private var start: MapCameraPosition {
    guard let newest else { return .automatic }
    return .region(
      MKCoordinateRegion(center: newest, latitudinalMeters: 1000, longitudinalMeters: 1000))
  }

  private var newest: CLLocationCoordinate2D? {
    places.filter { $0.at == nil }
      .max { ($0.times.first ?? .distantPast) < ($1.times.first ?? .distantPast) }
      .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
  }
}

/// The tapped spot: its name (his place's, then a label, or "No label"), how many visits it
/// holds, and a field to add or change the label; Save names every visit at the spot, on the
/// phone only (D-119). Inside one of his places it shows that place's note and "Edit place";
/// elsewhere "New place here" (S-053).
struct PlaceSpotCard: View {
  let visits: [PlaceRecord]
  let name: String?
  var mine: MyPlace?
  var place: () -> Void = {}
  let save: (String) -> Void
  @State private var label = ""

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spaceSm) {
      if visits.isEmpty {
        Text("No visit here").textStyle(.subtitle).accessibilityIdentifier("places.spot.none")
      } else {
        Text(name ?? "No label").textStyle(.headline).accessibilityIdentifier("places.spot.name")
        if let note = mine?.note {
          Text(note).textStyle(.subtitle).accessibilityIdentifier("places.spot.note")
        }
        Text("\(visits.count) visit\(visits.count == 1 ? "" : "s")").textStyle(.label)
          .foregroundStyle(Theme.muted)
        if mine == nil {
          HStack(spacing: Theme.spaceSm) {
            TextField("Label", text: $label).textStyle(.subtitle)
              .padding(.horizontal, Theme.spaceMd).frame(minHeight: Theme.sizeTarget)
              .background(Theme.surfaceRaised, in: Capsule())
              .accessibilityIdentifier("places.spot.field")
            Button("Save") { save(label) }.textStyle(.headline)
              .frame(minHeight: Theme.sizeTarget).accessibilityIdentifier("places.spot.save")
          }
        }
        Button(mine == nil ? "New place here" : "Edit place", action: place).textStyle(.headline)
          .frame(minHeight: Theme.sizeTarget).accessibilityIdentifier("places.spot.place")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(Theme.spaceCard)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    .onAppear { label = name ?? "" }
    .onChange(of: visits.first?.id) { label = name ?? "" }
  }
}

/// S-053: a place being drawn or edited. Save and Delete sit at the top, clear of the keyboard;
/// then the name, the optional note, and the radius, 25 to 400 m, with the visits inside.
struct PlaceEditor: View {
  @Binding var place: MyPlace
  let isNew: Bool
  let inside: Int
  let done: (_ delete: Bool) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spaceMd) {
      HStack(spacing: Theme.spaceMd) {
        Text(isNew ? "New place" : "Edit place").textStyle(.headline)
        Spacer()
        if !isNew {
          Button("Delete") { done(true) }.foregroundStyle(Theme.signalError)
            .accessibilityIdentifier("places.new.delete")
        }
        Button("Save") { done(false) }.textStyle(.headline)
          .disabled(place.name.trimmingCharacters(in: .whitespaces).isEmpty)
          .accessibilityIdentifier("places.new.save")
      }
      .frame(minHeight: Theme.sizeTarget)
      field("Name", text: $place.name, id: "places.new.name")
      field(
        "Context, for example Lift on Mon and Thu",
        text: Binding(get: { place.note ?? "" }, set: { place.note = $0 }), id: "places.new.note")
      HStack {
        Text("\(inside) visit\(inside == 1 ? "" : "s") inside").textStyle(.label)
          .accessibilityIdentifier("places.new.count")
        Spacer()
        Text("\(Int(place.radiusM)) m").textStyle(.label).foregroundStyle(Theme.muted)
      }
      Slider(value: $place.radiusM, in: 25...400).tint(Theme.ink)
        .accessibilityIdentifier("places.new.radius")
    }
    .padding(Theme.spaceCard).foregroundStyle(Theme.ink)
  }

  private func field(_ prompt: String, text: Binding<String>, id: String) -> some View {
    TextField(prompt, text: text).textStyle(.subtitle).padding(.horizontal, Theme.spaceMd)
      .frame(minHeight: Theme.sizeTarget).background(Theme.surfaceRaised, in: Capsule())
      .accessibilityIdentifier(id)
  }
}
