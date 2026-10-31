import Foundation
import XCTest

@testable import StezuCore

/// S-032: visits and significant changes are stored on the phone, then queued as `visit` and
/// `location` records. Every coordinate is made up (D-034).
final class LocationRecordTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)

  /// Records what happened, in order, across the location store and the sync queue.
  private final class Journal: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func add(_ entry: String) { lock.withLock { entries.append(entry) } }
    var all: [String] { lock.withLock { entries } }
  }

  private func payload(_ record: SyncRecord) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record))
    return try XCTUnwrap((object as? [String: Any])?["payload"] as? [String: Any], "no payload")
  }

  /// The arrival is stored and sent with no departure (NULL on the server); the departure then updates the same
  /// visit and resends its id with a newer `updated_at`, so there is still one visit.
  func testVisitIsUpdatedNotDuplicatedOnDeparture() throws {
    var log = LocationLog()
    let arrived = log.apply(
      .visit(arrival: start, departure: nil, latitude: 10.5, longitude: 20.5, accuracy: 35),
      at: start + 5)
    XCTAssertEqual(arrived.kind, "visit")
    var body = try payload(arrived)
    XCTAssertNil(body["departed_at"], "an unknown departure was sent")
    XCTAssertNotNil(body["arrived_at"] as? String)
    XCTAssertEqual(body["latitude"] as? Double, 10.5)
    XCTAssertEqual(body["longitude"] as? Double, 20.5)
    XCTAssertEqual(body["horizontal_accuracy_m"] as? Double, 35)
    let parts = Calendar.current.dateComponents([.year, .month, .day], from: start)
    let day = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    XCTAssertEqual(body["day"] as? String, day, "the day is not the phone's date")

    let departed = log.apply(
      .visit(
        arrival: start, departure: start + 3600, latitude: 10.5, longitude: 20.5, accuracy: 30),
      at: start + 3605)
    XCTAssertEqual(departed.id, arrived.id, "the departure made a new visit")
    XCTAssertGreaterThan(departed.updatedAt, arrived.updatedAt)
    XCTAssertEqual(log.places.count, 1)
    XCTAssertEqual(log.places.first?.times, [start, start + 3600])
    body = try payload(departed)
    XCTAssertNotNil(body["departed_at"] as? String)
    XCTAssertEqual(body["horizontal_accuracy_m"] as? Double, 30)

    // Another visit is a new one, and the record survives a reload with its payload.
    let other = log.apply(
      .visit(arrival: start + 7200, departure: nil, latitude: 11, longitude: 21, accuracy: 50),
      at: start + 7205)
    XCTAssertNotEqual(other.id, arrived.id)
    XCTAssertEqual(log.places.count, 2)
    let reloaded = try JSONDecoder().decode(
      SyncRecord.self, from: JSONEncoder().encode(departed))
    XCTAssertEqual(reloaded, departed)
  }

  /// Each event reaches the phone's store before it joins the sync queue; a significant change
  /// is a `location` record with no speed when none is known.
  func testEventsAreStoredBeforeQueueing() async throws {
    let journal = Journal()
    let recorder = LocationRecorder { log in
      journal.add("store \(log.places.count)")
    }
    let sync = HealthSync(state: SyncState()) { state in
      journal.add("queue \(state.pending.flatMap { $0.records ?? [] }.count)")
    }
    await recorder.record(
      .visit(arrival: start, departure: nil, latitude: 10, longitude: 20, accuracy: 40),
      into: sync, at: start + 1)
    await recorder.record(
      .fix(at: start + 600, latitude: 10.1, longitude: 20.1, accuracy: 500, speed: nil),
      into: sync, at: start + 601)
    XCTAssertEqual(journal.all, ["store 1", "queue 1", "store 2", "queue 2"])

    let records = await sync.state.pending.flatMap { $0.records ?? [] }
    XCTAssertEqual(records.map(\.kind), ["visit", "location"])
    let fix = try payload(records[1])
    XCTAssertNil(fix["speed_mps"], "an unknown speed was sent")
    XCTAssertNotNil(fix["at"] as? String)
    XCTAssertEqual(fix["horizontal_accuracy_m"] as? Double, 500)
    let log = await recorder.log
    XCTAssertEqual(log.places.flatMap(\.times).max(), start + 600)

    // A transport that fails keeps both records queued; nothing is dropped.
    let offline = FakeVMTransport(routes: [:], offline: true)
    await sync.run(health: nil, transport: offline)
    let kept = await sync.state.pending.flatMap { $0.records ?? [] }
    XCTAssertEqual(kept.count, 2)
  }

  /// Visits count by arrival inside the week; days count any visit end or fix on that day. An
  /// empty week is nil, not 0 of 7.
  func testPlacesWeekCountsDaysWithData() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
    let monday = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 0)))
    let week = DateInterval(start: monday, duration: 7 * 86_400)
    let hour: TimeInterval = 3600
    XCTAssertNil(LocationLog().week(week, calendar: calendar))

    var log = LocationLog()
    _ = log.apply(  // last week: no visit and no day this week
      .visit(
        arrival: monday - 30 * hour, departure: monday - 28 * hour, latitude: 1,
        longitude: 2, accuracy: 20), at: monday)
    _ = log.apply(  // Monday
      .visit(
        arrival: monday + 9 * hour, departure: monday + 10 * hour, latitude: 1,
        longitude: 2, accuracy: 20), at: monday)
    _ = log.apply(  // Tuesday arrival, Wednesday departure: two days
      .visit(
        arrival: monday + 47 * hour, departure: monday + 49 * hour, latitude: 1,
        longitude: 2, accuracy: 20), at: monday)
    _ = log.apply(  // Friday, a fix only
      .fix(at: monday + 4 * 24 * hour + hour, latitude: 1, longitude: 2, accuracy: 300, speed: 3),
      at: monday)
    _ = log.apply(  // Monday again: the day counts once
      .fix(at: monday + 12 * hour, latitude: 1, longitude: 2, accuracy: 300, speed: nil),
      at: monday)

    let places = try XCTUnwrap(log.week(week, calendar: calendar))
    XCTAssertEqual(places.visits, 2)
    XCTAssertEqual(places.daysWithData, 4)
    XCTAssertEqual(places.confidence.level, .medium)
    XCTAssertEqual(places.confidence.reason, "location on 4 of 7 days")
  }

  /// S-052: a visit is drawn to scale, as large as its accuracy but never under 15 m, and a fix
  /// is drawn smaller than any visit, however poor its accuracy.
  func testVisitRadiusUsesAccuracyWithFloor() {
    var log = LocationLog()
    _ = log.apply(
      .visit(arrival: start, departure: nil, latitude: 10.25, longitude: -30.5, accuracy: 40),
      at: start)
    _ = log.apply(
      .visit(arrival: start + 60, departure: nil, latitude: 10.5, longitude: -30.5, accuracy: 4),
      at: start)
    _ = log.apply(
      .fix(at: start + 120, latitude: 10.75, longitude: -30.5, accuracy: 500, speed: nil),
      at: start)
    XCTAssertEqual(log.places.map(\.mapRadius), [40, 15, 10])
    XCTAssertLessThan(
      log.places[2].mapRadius, log.places.filter { $0.at == nil }.map(\.mapRadius).min()!)
  }
}
