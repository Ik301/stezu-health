import Foundation

/// S-053 (D-133): a place Isaac draws, a named circle with an optional note, saved on the phone
/// in my-places.json first; S-056 (D-140) then queues it as a `my_place` record. Never logged.
public struct MyPlace: Codable, Sendable, Equatable, Identifiable {
  public var id, name: String
  public var note: String?
  public var latitude, longitude, radiusM: Double
  /// Stamped by the first save; nil only for a place drawn before S-056, until its backfill.
  public var createdAt: Date?

  public init(
    id: String, name: String, note: String? = nil, latitude: Double, longitude: Double,
    radiusM: Double = 75, createdAt: Date? = nil
  ) {
    (self.id, self.name, self.note) = (id, name, note)
    (self.latitude, self.longitude, self.radiusM) = (latitude, longitude, radiusM)
    self.createdAt = createdAt
  }

  public func contains(_ place: PlaceRecord) -> Bool {
    PlaceRecord.meters(latitude, longitude, place.latitude, place.longitude) <= radiusM
  }
}

/// His places. A visit takes the name of the smallest circle that contains it; a tie goes to the
/// earlier created, then the lower id, as on the server (D-141).
public struct MyPlaces: Codable, Sendable, Equatable {
  public var places: [MyPlace]

  public init(_ places: [MyPlace] = []) { self.places = places }

  public func place(for visit: PlaceRecord) -> MyPlace? {
    places.filter { $0.contains(visit) }.min {
      ($0.radiusM, $0.createdAt ?? .distantPast, $0.id)
        < ($1.radiusM, $1.createdAt ?? .distantPast, $1.id)
    }
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

  public func set(_ place: MyPlace, delete: Bool = false, at now: Date = Date()) -> MyPlaces {
    var place = place
    place.name = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
    place.note = place.note?.trimmingCharacters(in: .whitespacesAndNewlines)
    if place.note?.isEmpty == true { place.note = nil }
    place.createdAt = place.createdAt ?? places.places.first { $0.id == place.id }?.createdAt ?? now
    places.places.removeAll { $0.id == place.id }
    if !delete { places.places.append(place) }
    save(places)
    return places
  }

  /// S-056: saves first (D-076), then queues the place, or its tombstone, as one record.
  public func set(
    _ place: MyPlace, delete: Bool = false, into sync: HealthSync, at now: Date = Date()
  ) async -> MyPlaces {
    let saved = set(place, delete: delete, at: now)
    let live = delete ? nil : saved.places.first { $0.id == place.id }
    if let record = SyncRecord.myPlace(live, id: place.id, at: now) { await sync.enqueue([record]) }
    return saved
  }

  /// The first launch with S-056 stamps the places drawn before it, saves, and queues them all.
  public func backfill(into sync: HealthSync, at now: Date = Date()) async {
    guard await sync.state.myPlacesBackfilled != true else { return }
    for index in places.places.indices where places.places[index].createdAt == nil {
      places.places[index].createdAt = now
    }
    save(places)
    await sync.backfillMyPlaces(
      places.places.compactMap { SyncRecord.myPlace($0, id: $0.id, at: now) })
  }
}

/// A `my_place` payload (server/README.md), snake_case; `note` is sent as null when empty.
public struct MyPlaceRecord: Codable, Sendable, Equatable {
  public let id, name: String
  public let note: String?
  public let latitude, longitude, radiusM: Double
  public let createdAt: String

  enum CodingKeys: String, CodingKey {
    case id, name, note, latitude, longitude
    case radiusM = "radius_m"
    case createdAt = "created_at"
  }

  /// The server's limits; a record outside them would be rejected on every resend.
  var isValid: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && name.unicodeScalars.count <= 200 && (note?.unicodeScalars.count ?? 0) <= 1000
      && abs(latitude) <= 90 && abs(longitude) <= 180 && (10...2000).contains(radiusM)
  }

  public func encode(to encoder: any Encoder) throws {
    var box = encoder.container(keyedBy: CodingKeys.self)
    try box.encode(id, forKey: .id)
    try box.encode(name, forKey: .name)
    try box.encode(note, forKey: .note)  // null, not left out
    try box.encode(latitude, forKey: .latitude)
    try box.encode(longitude, forKey: .longitude)
    try box.encode(radiusM, forKey: .radiusM)
    try box.encode(createdAt, forKey: .createdAt)
  }
}
