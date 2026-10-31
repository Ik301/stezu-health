import Foundation

/// S-049 (D-119): what Apple knows at a coordinate. MapKit on the phone, a fake in `-uitest`.
/// It throws only `PlaceLookupThrottled`; any other failure is an empty lookup.
public protocol ReverseGeocoder: Sendable {
  func lookup(latitude: Double, longitude: Double, accuracy: Double) async throws -> PlaceLookup
}

/// Apple asked to slow down: no more lookups this launch (S-054).
public struct PlaceLookupThrottled: Error {
  public init() {}
}

/// S-054 (D-134): the names one lookup found, finest first.
public struct PlaceLookup: Sendable, Equatable {
  /// The nearest point of interest within `radius(accuracy:)`, ATMs and parking skipped.
  public var pointOfInterest: String?
  /// The reverse-geocoded placemark's name, nil when it is only a street address.
  public var placemark: String?
  /// The placemark's first area of interest, such as a whole campus.
  public var area: String?

  public init(pointOfInterest: String? = nil, placemark: String? = nil, area: String? = nil) {
    (self.pointOfInterest, self.placemark, self.area) = (pointOfInterest, placemark, area)
  }

  public var best: String? { pointOfInterest ?? placemark ?? area }

  /// The search radius around a visit, in metres: max(accuracy, 40) + 40, at most 150.
  public static func radius(accuracy: Double) -> Double { min(max(accuracy, 40) + 40, 150) }

  /// A placemark's name, unless its street address holds it (a street is not a place).
  public static func placeName(_ name: String?, address: String?) -> String? {
    guard let name, !name.isEmpty, address?.contains(name) != true else { return nil }
    return name
  }
}

/// place-names.json: names by visit id and the lookup version that saved each. A file from
/// before S-054 is a bare id-to-name map, read as version 1.
public struct SavedPlaceNames: Codable, Equatable, Sendable {
  public var names: [String: String]
  public var versions: [String: Int]

  public init(names: [String: String] = [:], versions: [String: Int] = [:]) {
    (self.names, self.versions) = (names, versions)
  }

  public static func decode(_ data: Data) -> SavedPlaceNames? {
    if let saved = try? JSONDecoder().decode(Self.self, from: data) { return saved }
    return (try? JSONDecoder().decode([String: String].self, from: data)).map { Self(names: $0) }
  }
}

/// Visit names by visit id, kept on the phone only. A name is never part of a PlaceRecord, so
/// it is never queued, synced or logged. An unnamed visit is looked up once a launch until it
/// has a name. A name saved by the version 1 (area-first) lookup is looked up again once, at
/// most 10 a launch, and replaced only if it was one of Apple's names; a label he typed stays.
/// One lookup runs at a time, and a throttling error ends lookups for the launch.
public actor PlaceNames {
  public static let version = 2
  public var names: [String: String] { saved.names }
  private var saved: SavedPlaceNames
  private var asked: Set<String> = []
  private var relooked = 0
  private var throttled = false
  private var running: Task<[String: String], Never>?
  private let geocoder: any ReverseGeocoder
  private let save: @Sendable (SavedPlaceNames) -> Void

  public init(
    saved: SavedPlaceNames, geocoder: any ReverseGeocoder,
    save: @escaping @Sendable (SavedPlaceNames) -> Void
  ) {
    (self.saved, self.geocoder, self.save) = (saved, geocoder, save)
  }

  /// Names already at this version; only the names are saved.
  public init(
    names: [String: String] = [:], geocoder: any ReverseGeocoder,
    save: @escaping @Sendable ([String: String]) -> Void = { _ in }
  ) {
    let saved = SavedPlaceNames(names: names, versions: names.mapValues { _ in Self.version })
    self.init(saved: saved, geocoder: geocoder) { save($0.names) }
  }

  /// Isaac's own label for a spot: every visit id given gets it, replacing a looked-up name,
  /// and is saved; an empty label removes the names. Returns every name.
  public func label(_ label: String, visits ids: [String]) -> [String: String] {
    let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
    for id in ids {
      saved.names[id] = label.isEmpty ? nil : label
      saved.versions[id] = label.isEmpty ? nil : Self.version
    }
    save(saved)
    return names
  }

  /// Names these places' visits (fixes are skipped) once any pass already running is done;
  /// returns every name.
  public func name(_ places: [PlaceRecord]) async -> [String: String] {
    let previous = running
    let pass = Task {
      _ = await previous?.value
      return await self.lookUp(places)
    }
    running = pass
    return await pass.value
  }

  private func lookUp(_ places: [PlaceRecord]) async -> [String: String] {
    for visit in places where visit.isVisit && !throttled {
      let old = saved.names[visit.id]
      let stale = old != nil && saved.versions[visit.id, default: 1] < Self.version
      guard old == nil || (stale && relooked < 10), asked.insert(visit.id).inserted else {
        continue
      }
      if stale { relooked += 1 }
      do {
        let found = try await geocoder.lookup(
          latitude: visit.latitude, longitude: visit.longitude,
          accuracy: visit.horizontalAccuracyM)
        guard let best = found.best else { continue }
        if old == nil || old == found.area || old == found.placemark {
          saved.names[visit.id] = best
        }
        saved.versions[visit.id] = Self.version
        save(saved)
      } catch {
        throttled = true
      }
    }
    return names
  }
}

/// The `-uitest` geocoder: a point of interest by latitude and one area everywhere, counting
/// its lookups; past `limit` lookups it throws `PlaceLookupThrottled`.
public actor FakeReverseGeocoder: ReverseGeocoder {
  public private(set) var lookups = 0
  private let names: [Double: String]
  private let area: String?
  private let limit: Int

  public init(names: [Double: String], area: String? = nil, limit: Int = .max) {
    (self.names, self.area, self.limit) = (names, area, limit)
  }

  public func lookup(latitude: Double, longitude: Double, accuracy: Double) throws -> PlaceLookup {
    guard lookups < limit else { throw PlaceLookupThrottled() }
    lookups += 1
    return PlaceLookup(pointOfInterest: names[latitude], area: area)
  }
}
