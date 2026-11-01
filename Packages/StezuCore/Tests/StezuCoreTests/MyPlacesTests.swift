import Foundation
import XCTest

@testable import StezuCore

/// S-056 (D-140): every save of one of his places queues one `my_place` record after
/// my-places.json is written, and the places drawn before S-056 are queued once. All made up.
final class MyPlacesTests: XCTestCase {
  private func payloads(_ sync: HealthSync) async throws -> [[String: Any]] {
    try await sync.state.pending.flatMap { $0.records ?? [] }.map {
      try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) as? [String: Any])
    }
  }

  func testEditQueuesMyPlaceRecord() async throws {
    let events = Events()
    let store = MyPlacesStore { events.add("save \($0.places.count)") }
    let sync = HealthSync(state: SyncState()) { events.add("queue \($0.pending.count)") }
    let t0 = Date(timeIntervalSince1970: 1_800_000_000.123)
    var gym = MyPlace(id: "p-1", name: " Gym ", note: "  ", latitude: 10.25, longitude: -30.5)

    // Create: saved first, then one record with the snake_case payload and a null note.
    _ = await store.set(gym, into: sync, at: t0)
    XCTAssertEqual(events.all.prefix(2), ["save 1", "queue 1"], "the local save comes first")
    var sent = try await payloads(sync)
    XCTAssertEqual(sent.count, 1)
    XCTAssertEqual(sent[0]["kind"] as? String, "my_place")
    XCTAssertEqual(sent[0]["id"] as? String, "p-1")
    XCTAssertEqual(sent[0]["deleted"] as? Bool, false)
    let payload = try XCTUnwrap(sent[0]["payload"] as? [String: Any])
    XCTAssertEqual(
      Set(payload.keys),
      ["id", "name", "note", "latitude", "longitude", "radius_m", "created_at"])
    XCTAssertEqual(payload["id"] as? String, "p-1", "the payload id is the record id")
    XCTAssertEqual(payload["name"] as? String, "Gym")
    XCTAssertTrue(payload["note"] is NSNull, "an empty note is sent as null")
    XCTAssertEqual(payload["radius_m"] as? Double, 75)
    let stamp = SyncRecord.stamp(t0, .current)
    XCTAssertEqual(payload["created_at"] as? String, stamp)
    XCTAssertEqual(sent[0]["updated_at"] as? String, stamp)
    XCTAssertTrue(stamp.contains(".123"), "updated_at has milliseconds: \(stamp)")

    // Move and resize: the same id, a newer updated_at, the first created_at.
    (gym.latitude, gym.radiusM, gym.note) = (10.26, 120, "Lift days")
    _ = await store.set(gym, into: sync, at: t0 + 60)
    sent = try await payloads(sync)
    XCTAssertEqual(sent.count, 2)
    let moved = try XCTUnwrap(sent[1]["payload"] as? [String: Any])
    XCTAssertEqual(sent[1]["id"] as? String, "p-1")
    XCTAssertEqual(moved["latitude"] as? Double, 10.26)
    XCTAssertEqual(moved["radius_m"] as? Double, 120)
    XCTAssertEqual(moved["note"] as? String, "Lift days")
    XCTAssertEqual(moved["created_at"] as? String, stamp, "created_at never changes")
    XCTAssertEqual(sent[1]["updated_at"] as? String, SyncRecord.stamp(t0 + 60, .current))

    // Delete: the same id as a tombstone, after the file no longer has it.
    let left = await store.set(gym, delete: true, into: sync, at: t0 + 120)
    XCTAssertTrue(left.places.isEmpty)
    sent = try await payloads(sync)
    XCTAssertEqual(sent.count, 3)
    XCTAssertEqual(sent[2]["id"] as? String, "p-1")
    XCTAssertEqual(sent[2]["deleted"] as? Bool, true)
    XCTAssertNil(sent[2]["payload"] as? [String: Any])

    // A place the server would reject is saved on the phone but never queued.
    let huge = MyPlace(id: "p-2", name: "Far", latitude: 10, longitude: -30, radiusM: 5000)
    let kept = await store.set(huge, into: sync, at: t0 + 180)
    XCTAssertEqual(kept.places.map(\.id), ["p-2"])
    let records = await sync.state.pending.count
    XCTAssertEqual(records, 3, "radius_m above 2000 was queued")

    // The queue survives a relaunch: a saved state with a my_place decodes again.
    let state = await sync.state
    let decoded = try JSONDecoder().decode(SyncState.self, from: JSONEncoder().encode(state))
    XCTAssertEqual(decoded, state)
    XCTAssertEqual(decoded.pending[0].records?[0].myPlacePayload?.name, "Gym")
  }

  func testBackfillQueuesExistingPlacesOnce() async throws {
    // Two places drawn before S-056 (no created_at yet) and one drawn after.
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let saved = Saved()
    let store = MyPlacesStore(
      MyPlaces([
        MyPlace(id: "a", name: "Library", latitude: 10.25, longitude: -30.5),
        MyPlace(id: "b", name: "Gym", latitude: 10.26, longitude: -30.5, radiusM: 50),
        MyPlace(
          id: "c", name: "Pool", latitude: 10.27, longitude: -30.5, createdAt: t0 - 86_400),
      ])
    ) { saved.set($0) }
    let sync = HealthSync(state: SyncState())

    await store.backfill(into: sync, at: t0)
    var state = await sync.state
    XCTAssertEqual(state.myPlacesBackfilled, true)
    XCTAssertEqual(state.pending.count, 1, "one batch for the backfill")
    let records = state.pending[0].records ?? []
    XCTAssertEqual(records.map(\.kind), ["my_place", "my_place", "my_place"])
    XCTAssertEqual(records.compactMap(\.myPlacePayload?.name), ["Library", "Gym", "Pool"])
    XCTAssertEqual(
      records.compactMap(\.myPlacePayload?.createdAt),
      [t0, t0, t0 - 86_400].map { SyncRecord.stamp($0, .current) },
      "the old places are stamped once, a stamped one keeps its time")
    XCTAssertEqual(
      saved.value?.places.map(\.createdAt), [t0, t0, t0 - 86_400],
      "the stamps are saved on the phone")

    // A second launch, and one after a relaunch from the saved state, queue nothing more.
    await store.backfill(into: sync, at: t0 + 60)
    state = await sync.state
    XCTAssertEqual(state.pending.count, 1, "the backfill ran twice")
    let relaunched = HealthSync(
      state: try JSONDecoder().decode(SyncState.self, from: JSONEncoder().encode(state)))
    await store.backfill(into: relaunched, at: t0 + 120)
    let again = await relaunched.state.pending.count
    XCTAssertEqual(again, 1, "the flag did not survive a relaunch")

    // An empty install sets the flag and queues no batch.
    let empty = HealthSync(state: SyncState())
    await MyPlacesStore().backfill(into: empty, at: t0)
    let flag = await empty.state.myPlacesBackfilled
    let none = await empty.state.pending.count
    XCTAssertEqual(flag, true)
    XCTAssertEqual(none, 0)
  }

  func testTieGoesToEarlierCreatedThenLowerID() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var log = LocationLog()
    let arrival = LocationEvent.visit(
      arrival: t0, departure: nil, latitude: 10.25, longitude: -30.5, accuracy: 40)
    _ = log.apply(arrival, at: t0)
    let visit = log.places[0]
    let late = MyPlace(id: "a", name: "Late", latitude: 10.25, longitude: -30.5, createdAt: t0)
    let early = MyPlace(
      id: "b", name: "Early", latitude: 10.25, longitude: -30.5, createdAt: t0 - 60)
    XCTAssertEqual(MyPlaces([late, early]).place(for: visit)?.name, "Early")
    let twin = MyPlace(id: "c", name: "Twin", latitude: 10.25, longitude: -30.5, createdAt: t0)
    XCTAssertEqual(MyPlaces([twin, late]).place(for: visit)?.name, "Late", "lower id wins")
  }
}

private final class Events: @unchecked Sendable {
  private let lock = NSLock()
  private var events: [String] = []
  var all: [String] { lock.withLock { events } }
  func add(_ event: String) { lock.withLock { events.append(event) } }
}

private final class Saved: @unchecked Sendable {
  private let lock = NSLock()
  private var places: MyPlaces?
  var value: MyPlaces? { lock.withLock { places } }
  func set(_ places: MyPlaces) { lock.withLock { self.places = places } }
}
