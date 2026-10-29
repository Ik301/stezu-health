import StezuCore
import XCTest

/// The Places heat map: a tap finds the visits at that spot, and a label names them all, on the
/// phone only. Coordinates are made up (D-034).
final class PlaceLabelTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_014_400)

  private func log() -> LocationLog {
    var log = LocationLog()
    let events: [LocationEvent] = [
      .visit(
        arrival: now - 7200, departure: now - 3600, latitude: 10.25, longitude: -30.5,
        accuracy: 40),
      .visit(
        arrival: now - 1800, departure: nil, latitude: 10.2503, longitude: -30.5, accuracy: 40),
      .fix(at: now - 900, latitude: 10.25, longitude: -30.5, accuracy: 500, speed: nil),
      .visit(arrival: now - 600, departure: nil, latitude: 10.75, longitude: -30, accuracy: 50),
    ]
    for event in events { _ = log.apply(event, at: now) }
    return log
  }

  func testMetersBetweenCoordinates() {
    XCTAssertEqual(PlaceRecord.meters(10.25, -30.5, 10.25, -30.5), 0, accuracy: 0.001)
    // 0.0003 degrees of latitude is about 33 m.
    XCTAssertEqual(PlaceRecord.meters(10.25, -30.5, 10.2503, -30.5), 33.4, accuracy: 0.5)
  }

  func testTapFindsTheSpotsVisitsNearestFirstAndNoFixes() {
    let log = log()
    let spot = log.visits(near: 10.2502, -30.5, within: 100)
    XCTAssertEqual(spot.count, 2, "the fix is not a visit, the far visit is out of reach")
    XCTAssertEqual(spot.first?.latitude, 10.2503)
    XCTAssertTrue(log.visits(near: 0, 0, within: 100).isEmpty)
  }

  func testLabelNamesEveryVisitAtTheSpotAndSaves() async {
    let saved = SavedNames()
    let names = PlaceNames(
      names: ["a": "Looked up"], geocoder: FakeReverseGeocoder(names: [:]),
      save: { saved.set($0) })
    var all = await names.label("  Study room ", visits: ["a", "b"])
    XCTAssertEqual(all, ["a": "Study room", "b": "Study room"])
    all = await names.label("", visits: ["b"])
    XCTAssertEqual(all, ["a": "Study room"], "an empty label removes the name")
    XCTAssertEqual(saved.get(), all)
  }
}

private final class SavedNames: @unchecked Sendable {
  private let lock = NSLock()
  private var names: [String: String] = [:]
  func set(_ names: [String: String]) { lock.withLock { self.names = names } }
  func get() -> [String: String] { lock.withLock { names } }
}
