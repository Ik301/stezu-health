import CoreLocation
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

/// S-049: Apple's reverse geocoding; the point of interest, else the placemark's name. The
/// coordinates go to Apple for the lookup (D-119); nil when offline or nothing is found.
struct AppleReverseGeocoder: ReverseGeocoder {
  func name(latitude: Double, longitude: Double) async -> String? {
    let place = CLLocation(latitude: latitude, longitude: longitude)
    let mark = try? await CLGeocoder().reverseGeocodeLocation(place).first
    return mark?.areasOfInterest?.first ?? mark?.name
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

  /// S-049 (D-119): visit names in place-names.json beside the log, from Apple's geocoder.
  static func placeNamesFile(storage: StorageMode) -> PlaceNames {
    let file = FinishedWorkoutStore(storage: storage).file?.deletingLastPathComponent()
      .appendingPathComponent("place-names.json")
    let saved = file.flatMap {
      try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: $0))
    }
    return PlaceNames(names: saved ?? [:], geocoder: AppleReverseGeocoder()) { names in
      guard let file, let data = try? JSONEncoder().encode(names) else { return }
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
