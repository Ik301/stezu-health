import Foundation

/// S-032: a CLVisit or a significant change; unknown ends (distantPast/Future) and speeds are nil.
public enum LocationEvent: Sendable, Equatable {
  case visit(
    arrival: Date?, departure: Date?, latitude: Double, longitude: Double, accuracy: Double)
  case fix(at: Date, latitude: Double, longitude: Double, accuracy: Double, speed: Double?)
}

public enum LocationPermission: String, Sendable {
  case always = "Always"
  case whileUsing = "While Using"
  case off = "Off"
}

/// CLLocationManager's visits and significant changes, or the `-uitest` fixture. `requestAccess`
/// asks for When In Use, then Always; `start` monitors once access is Always.
public protocol LocationSource: Sendable {
  func permission() async -> LocationPermission
  func requestAccess() async
  func start(_ deliver: @escaping @Sendable (LocationEvent) async -> Void) async
}

/// A visit or fix as stored on the phone and sent as a `visit` or `location` payload
/// (server/README.md). An unknown value is left out, which the server reads as NULL.
public struct PlaceRecord: Codable, Sendable, Equatable {
  public let id, day: String
  public var arrivedAt, departedAt, at: String?
  public var latitude, longitude, horizontalAccuracyM: Double
  public var speedMps: Double?

  enum CodingKeys: String, CodingKey {
    case id, day, at, latitude, longitude
    case arrivedAt = "arrived_at"
    case departedAt = "departed_at"
    case horizontalAccuracyM = "horizontal_accuracy_m"
    case speedMps = "speed_mps"
  }

  var isVisit: Bool { at == nil }
  static let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
  public var times: [Date] {
    [arrivedAt, departedAt, at].compactMap { try? $0.map(Self.iso.parse) }
  }
}

/// Every visit and fix, kept on the phone (D-076) before anything is queued.
public struct LocationLog: Codable, Sendable, Equatable {
  public var places: [PlaceRecord] = []

  public init() {}

  /// Stores the event and returns its record. A visit's id comes from its arrival, so its
  /// departure replaces it under the same id and the server updates it.
  public mutating func apply(_ event: LocationEvent, at now: Date) -> SyncRecord {
    let stamp = { (date: Date) in SyncRecord.stamp(date, .current) }
    let ms = { (date: Date) in Int64((date.timeIntervalSince1970 * 1000).rounded()) }
    let place: PlaceRecord
    switch event {
    case .visit(let arrival, let departure, let latitude, let longitude, let accuracy):
      let key = arrival ?? departure ?? now
      place = PlaceRecord(
        id: "visit.\(ms(key))", day: String(stamp(key).prefix(10)), arrivedAt: arrival.map(stamp),
        departedAt: departure.map(stamp), latitude: latitude, longitude: longitude,
        horizontalAccuracyM: accuracy)
    case .fix(let at, let latitude, let longitude, let accuracy, let speed):
      place = PlaceRecord(
        id: "location.\(ms(at))", day: String(stamp(at).prefix(10)), at: stamp(at),
        latitude: latitude, longitude: longitude, horizontalAccuracyM: accuracy, speedMps: speed)
    }
    places.removeAll { $0.id == place.id }
    places.append(place)
    return SyncRecord(
      kind: place.isVisit ? "visit" : "location", id: place.id, updatedAt: stamp(now),
      deleted: false, placePayload: place)
  }

  /// Data's Places row: nil when the week has no visit and no fix, never 0 of 7.
  public func week(_ week: DateInterval, calendar: Calendar = .current) -> PlacesWeek? {
    let visits = places.filter { $0.isVisit && $0.times.first.map(week.contains) == true }
    let days = Set(places.flatMap(\.times).filter(week.contains).map(calendar.startOfDay))
    guard !days.isEmpty else { return nil }
    let level: Confidence.Level = days.count >= 5 ? .high : days.count >= 3 ? .medium : .low
    let perDay = (0..<7).map { offset -> Double? in
      guard let day = calendar.date(byAdding: .day, value: offset, to: week.start),
        days.contains(day)
      else { return nil }
      return Double(visits.filter { calendar.isDate($0.times[0], inSameDayAs: day) }.count)
    }
    return PlacesWeek(
      visits: visits.count, daysWithData: days.count, perDay: perDay,
      confidence: Confidence(level: level, reason: "location on \(days.count) of 7 days"))
  }
}

extension LocationLog {
  /// The heat map's spot under a tap: the visits within `meters` of the point, nearest first.
  public func visits(near latitude: Double, _ longitude: Double, within meters: Double)
    -> [PlaceRecord]
  {
    places.filter(\.isVisit)
      .map { ($0, PlaceRecord.meters(latitude, longitude, $0.latitude, $0.longitude)) }
      .filter { $0.1 <= meters }.sorted { $0.1 < $1.1 }.map(\.0)
  }
}

extension PlaceRecord {
  /// The heat map's circle, in metres (S-052): a visit is drawn as large as its accuracy, at
  /// least 15 m; a fix is a 10 m dot, smaller than any visit.
  public var mapRadius: Double { isVisit ? max(horizontalAccuracyM, 15) : 10 }

  /// The great-circle distance between two coordinates, in metres.
  public static func meters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double)
    -> Double
  {
    let rad = Double.pi / 180
    let a =
      pow(sin((lat2 - lat1) * rad / 2), 2)
      + cos(lat1 * rad) * cos(lat2 * rad) * pow(sin((lon2 - lon1) * rad / 2), 2)
    return 6_371_000 * 2 * atan2(sqrt(a), sqrt(1 - a))
  }
}

/// Holds the log: each event is saved on the phone first, then joins `sync`'s queue.
public actor LocationRecorder {
  public private(set) var log: LocationLog
  private let save: @Sendable (LocationLog) -> Void

  public init(log: LocationLog = LocationLog(), save: @escaping @Sendable (LocationLog) -> Void) {
    (self.log, self.save) = (log, save)
  }

  public func record(_ event: LocationEvent, into sync: HealthSync, at now: Date = Date()) async {
    let record = log.apply(event, at: now)
    save(log)
    await sync.enqueue([record])
  }
}

/// This week's visits (by arrival) and the days with any location data. `perDay` counts the
/// visits that arrived on each day, Monday to Sunday: 0 on a day with location data but no
/// visit, nil on a day without location data (S-048).
public struct PlacesWeek: Sendable, Equatable {
  public let visits, daysWithData: Int
  public let perDay: [Double?]
  public let confidence: Confidence
}
