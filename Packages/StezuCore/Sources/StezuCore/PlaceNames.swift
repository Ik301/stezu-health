import Foundation

/// S-049 (D-119): a place's name for a coordinate. CLGeocoder on the phone, a fake in `-uitest`.
public protocol ReverseGeocoder: Sendable {
  func name(latitude: Double, longitude: Double) async -> String?
}

/// Visit names by visit id, kept on the phone only (place-names.json). A name is never part of a
/// PlaceRecord, so it is never queued, synced or logged. Each visit is looked up once a launch
/// until it has a name; a found name is saved and never looked up again.
public actor PlaceNames {
  public private(set) var names: [String: String]
  private var asked: Set<String> = []
  private let geocoder: any ReverseGeocoder
  private let save: @Sendable ([String: String]) -> Void

  public init(
    names: [String: String] = [:], geocoder: any ReverseGeocoder,
    save: @escaping @Sendable ([String: String]) -> Void = { _ in }
  ) {
    (self.names, self.geocoder, self.save) = (names, geocoder, save)
  }

  /// Isaac's own label for a spot: every visit id given gets it, replacing a looked-up name,
  /// and is saved; an empty label removes the names. Returns every name.
  public func label(_ label: String, visits ids: [String]) -> [String: String] {
    let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
    for id in ids { names[id] = label.isEmpty ? nil : label }
    save(names)
    return names
  }

  /// Names these places' visits (fixes are skipped), one lookup at a time; returns every name.
  public func name(_ places: [PlaceRecord]) async -> [String: String] {
    for visit in places where visit.isVisit && names[visit.id] == nil {
      guard asked.insert(visit.id).inserted,
        let name = await geocoder.name(latitude: visit.latitude, longitude: visit.longitude)
      else { continue }
      names[visit.id] = name
      save(names)
    }
    return names
  }
}

/// The `-uitest` geocoder: a name by latitude, counting its lookups.
public actor FakeReverseGeocoder: ReverseGeocoder {
  public private(set) var lookups = 0
  private let names: [Double: String]

  public init(names: [Double: String]) { self.names = names }

  public func name(latitude: Double, longitude: Double) -> String? {
    lookups += 1
    return names[latitude]
  }
}
