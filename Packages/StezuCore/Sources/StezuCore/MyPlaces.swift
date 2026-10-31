import Foundation

/// S-053 (D-133): a place Isaac draws, a named circle with an optional note. Kept on the phone
/// only (my-places.json), never in a PlaceRecord, so it is never queued, synced or logged.
public struct MyPlace: Codable, Sendable, Equatable, Identifiable {
  public var id, name: String
  public var note: String?
  public var latitude, longitude, radiusM: Double

  public init(
    id: String, name: String, note: String? = nil, latitude: Double, longitude: Double,
    radiusM: Double = 75
  ) {
    (self.id, self.name, self.note) = (id, name, note)
    (self.latitude, self.longitude, self.radiusM) = (latitude, longitude, radiusM)
  }

  public func contains(_ place: PlaceRecord) -> Bool {
    PlaceRecord.meters(latitude, longitude, place.latitude, place.longitude) <= radiusM
  }
}

/// His places. A visit takes the name of the smallest circle that contains it.
public struct MyPlaces: Codable, Sendable, Equatable {
  public var places: [MyPlace]

  public init(_ places: [MyPlace] = []) { self.places = places }

  public func place(for visit: PlaceRecord) -> MyPlace? {
    places.filter { $0.contains(visit) }.min { $0.radiusM < $1.radiusM }
  }

  /// A visit's name: his place, then the looked-up name; nil leaves the visit's times.
  public func name(_ visit: PlaceRecord, looked names: [String: String]) -> String? {
    place(for: visit)?.name ?? names[visit.id]
  }
}

/// Holds his places: a save adds or replaces a place by id (a delete removes it), trims its
/// name and note, writes the file and returns them all.
public actor MyPlacesStore {
  public private(set) var places: MyPlaces
  private let save: @Sendable (MyPlaces) -> Void

  public init(
    _ places: MyPlaces = MyPlaces(), save: @escaping @Sendable (MyPlaces) -> Void = { _ in }
  ) {
    (self.places, self.save) = (places, save)
  }

  public func set(_ place: MyPlace, delete: Bool = false) -> MyPlaces {
    var place = place
    place.name = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
    place.note = place.note?.trimmingCharacters(in: .whitespacesAndNewlines)
    if place.note?.isEmpty == true { place.note = nil }
    places.places.removeAll { $0.id == place.id }
    if !delete { places.places.append(place) }
    save(places)
    return places
  }
}
