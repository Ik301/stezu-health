import CoreLocation
import MapKit
import StezuCore

/// S-032: visits and significant changes (no continuous GPS) wake or relaunch the app.
final class CoreLocationSource: NSObject, LocationSource, CLLocationManagerDelegate,
  @unchecked Sendable
{
  private let manager = CLLocationManager()  // made on the main thread; delegate calls land there
  private var deliver: (@Sendable (LocationEvent) async -> Void)?
  private var asked = false  // Allow asked for When In Use; Always follows

  func permission() async -> LocationPermission {
    let status = manager.authorizationStatus
    return status == .authorizedAlways
      ? .always : status == .authorizedWhenInUse ? .whileUsing : .off
  }

  func requestAccess() async {
    await MainActor.run {
      asked = manager.authorizationStatus == .notDetermined
      _ = asked ? manager.requestWhenInUseAuthorization() : manager.requestAlwaysAuthorization()
    }
  }

  /// Monitoring starts once `deliver` is set (and access is Always), so no event comes before.
  func start(_ deliver: @escaping @Sendable (LocationEvent) async -> Void) async {
    await MainActor.run {
      self.deliver = deliver
      manager.delegate = self
      locationManagerDidChangeAuthorization(manager)
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if asked, manager.authorizationStatus == .authorizedWhenInUse {
      asked = false
      manager.requestAlwaysAuthorization()  // the second step, from the same tap
    }
    guard manager.authorizationStatus == .authorizedAlways, deliver != nil else { return }
    manager.startMonitoringVisits()
    manager.startMonitoringSignificantLocationChanges()
  }

  func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    let event = LocationEvent.visit(
      arrival: visit.arrivalDate == .distantPast ? nil : visit.arrivalDate,
      departure: visit.departureDate == .distantFuture ? nil : visit.departureDate,
      latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude,
      accuracy: visit.horizontalAccuracy)
    if let deliver { Task { await deliver(event) } }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    for fix in locations {
      let event = LocationEvent.fix(
        at: fix.timestamp, latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude,
        accuracy: fix.horizontalAccuracy, speed: fix.speed < 0 ? nil : fix.speed)
      if let deliver { Task { await deliver(event) } }
    }
  }
}

/// S-054 (D-134): the nearest point of interest within the visit's radius (not an ATM, EV
/// charger or car park), the placemark's name unless it is a street address, and its first
/// area of interest; `PlaceLookup.best` picks in that order. Both requests always run, so an
/// old campus-wide name can be recognised as Apple's (D-138). The coordinates go to Apple for
/// the lookup (D-119). A failure is an empty part, except Apple's throttling, which is thrown.
struct AppleReverseGeocoder: ReverseGeocoder {
  func lookup(latitude: Double, longitude: Double, accuracy: Double) async throws -> PlaceLookup {
    try await Self.find(CLLocation(latitude: latitude, longitude: longitude), accuracy: accuracy)
  }

  @MainActor private static func find(_ here: CLLocation, accuracy: Double) async throws
    -> PlaceLookup
  {
    let request = MKLocalPointsOfInterestRequest(
      center: here.coordinate, radius: PlaceLookup.radius(accuracy: accuracy))
    request.pointOfInterestFilter = MKPointOfInterestFilter(excluding: [.atm, .evCharger, .parking])
    var items: [MKMapItem] = []
    do { items = try await MKLocalSearch(request: request).start().mapItems } catch {
      try rethrowThrottling(error)
    }
    let distance = { (item: MKMapItem) in item.placemark.location?.distance(from: here) ?? 1e9 }
    var found = PlaceLookup(pointOfInterest: items.min { distance($0) < distance($1) }?.name)
    if #available(iOS 26, *) {
      let geocoding: MKReverseGeocodingRequest? = MKReverseGeocodingRequest(location: here)
      var item: MKMapItem?
      do { item = try await geocoding?.mapItems.first } catch { try rethrowThrottling(error) }
      found.placemark = PlaceLookup.placeName(item?.name, address: item?.address?.fullAddress)
      found.area = item?.placemark.areasOfInterest?.first
      return found
    }
    var mark: CLPlacemark?
    do { mark = try await CLGeocoder().reverseGeocodeLocation(here).first } catch {
      try rethrowThrottling(error)
    }
    let street = [mark?.subThoroughfare, mark?.thoroughfare].compactMap { $0 }
    found.placemark = PlaceLookup.placeName(mark?.name, address: street.joined(separator: " "))
    found.area = mark?.areasOfInterest?.first
    return found
  }

  /// Apple's rate limit: MapKit's loadingThrottled, or the geocoder's network error.
  private static func rethrowThrottling(_ error: any Error) throws {
    let code = (error as? MKError)?.code
    if code == .loadingThrottled || (error as? CLError)?.code == .network {
      throw PlaceLookupThrottled()
    }
  }
}

/// The `-uitest` source: Always with the scenario's events, Off without any.
struct FixtureLocationSource: LocationSource {
  let events: [LocationEvent]
  func permission() -> LocationPermission { events.isEmpty ? .off : .always }
  func requestAccess() {}
  func start(_ deliver: @escaping @Sendable (LocationEvent) async -> Void) async {
    for event in events { await deliver(event) }
  }
}

extension AppEnvironment {
  /// The log in location-log.json next to the sync state; memory under `-uitest`.
  static func placesFile(storage: StorageMode) -> LocationRecorder {
    let file = FinishedWorkoutStore(storage: storage).file?.deletingLastPathComponent()
      .appendingPathComponent("location-log.json")
    let saved = file.flatMap {
      try? JSONDecoder().decode(LocationLog.self, from: Data(contentsOf: $0))
    }
    return LocationRecorder(log: saved ?? LocationLog()) { log in
      guard let file, let data = try? JSONEncoder().encode(log) else { return }
      try? FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: file, options: .atomic)
    }
  }

  /// S-049 (D-119): place-names.json beside the log.
  static func placeNamesURL(storage: StorageMode) -> URL? {
    FinishedWorkoutStore(storage: storage).file?.deletingLastPathComponent()
      .appendingPathComponent("place-names.json")
  }

  /// Visit names and their lookup versions in place-names.json (S-054), from Apple's geocoder.
  static func placeNamesFile(
    storage: StorageMode, geocoder: any ReverseGeocoder = AppleReverseGeocoder()
  ) -> PlaceNames {
    let file = placeNamesURL(storage: storage)
    let saved = file.flatMap { try? Data(contentsOf: $0) }.flatMap(SavedPlaceNames.decode)
    return PlaceNames(saved: saved ?? SavedPlaceNames(), geocoder: geocoder) { saved in
      guard let file, let data = try? JSONEncoder().encode(saved) else { return }
      try? data.write(to: file, options: .atomic)
    }
  }

  /// S-053 (D-133): his own places in my-places.json beside the log.
  static func myPlacesFile(storage: StorageMode) -> MyPlacesStore {
    let file = FinishedWorkoutStore(storage: storage).file?.deletingLastPathComponent()
      .appendingPathComponent("my-places.json")
    let saved = file.flatMap {
      try? JSONDecoder().decode(MyPlaces.self, from: Data(contentsOf: $0))
    }
    return MyPlacesStore(saved ?? MyPlaces()) { places in
      guard let file, let data = try? JSONEncoder().encode(places) else { return }
      try? data.write(to: file, options: .atomic)
    }
  }

  /// At every launch, background relaunches too: save, queue (D-076), then one pass.
  func startLocation() {
    Task {
      await locationSource.start { event in
        await places.record(event, into: healthSync)
        await syncHermes()
      }
    }
  }
}
