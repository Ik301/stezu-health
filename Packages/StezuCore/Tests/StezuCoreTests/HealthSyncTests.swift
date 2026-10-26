import Foundation
import XCTest

@testable import StezuCore

/// S-028: Health changes reach POST /sync in batches of about 2,000 keyed by HealthKit UUID,
/// deletions included; a batch that fails stays queued and is resent with the same batch id.
/// Every value is synthetic.
final class HealthSyncTests: XCTestCase {
  /// Every state the engine saved, as the app's file would see it.
  final class SavedStates: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [SyncState] = []
    var last: SyncState? { lock.withLock { states.last } }
    func append(_ state: SyncState) { lock.withLock { states.append(state) } }
  }

  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let ok = VMResponse(
    status: 200, body: Data(#"{"accepted": 1, "duplicates": 0, "deleted": 0, "rejected": 0}"#.utf8))
  private let status = VMResponse(
    status: 200, body: Data(#"{"samples_total": 2500, "records_total": 0, "devices": []}"#.utf8))

  private func sample(_ index: Int) -> SyncSample {
    SyncSample(
      uuid: "SAMPLE-\(index)", type: "HKQuantityTypeIdentifierStepCount",
      start: "2027-01-15T08:00:00-05:00", end: "2027-01-15T08:05:00-05:00", value: 10,
      unit: "count", sourceName: "Example Phone", sourceBundle: "com.example.phone")
  }

  private func batches(_ transport: FakeVMTransport) async throws -> [SyncBatch] {
    try await transport.sent.filter { $0.route == "POST /sync" }
      .map { try JSONDecoder().decode(SyncBatch.self, from: $0.body ?? Data()) }
  }

  func testBatchesAreIdempotentByID() async throws {
    let health = FakeHealthStore(changes: [.stepCount: (0..<2500).map { .added(sample($0)) }])
    let transport = FakeVMTransport(routes: ["POST /sync": ok, "GET /sync/status": status])
    let sync = HealthSync(state: SyncState(deviceID: "DEVICE-1"))
    let initial = await sync.state
    XCTAssertNil(initial.lastSyncAt, "a sync time before the first sync")

    let result = await sync.run(health: health, transport: transport, now: now)
    let sent = try await batches(transport)
    XCTAssertEqual(sent.map(\.samples.count), [2000, 500], "about 2,000 samples per request")
    XCTAssertEqual(Set(sent.flatMap(\.samples).map(\.uuid)).count, 2500, "each sample once")
    XCTAssertEqual(Set(sent.map(\.batchID)).count, 2, "every batch has its own id")
    XCTAssertTrue(sent.allSatisfy { $0.deviceID == "DEVICE-1" })
    let requests = await transport.sent
    let body = String(decoding: requests.first?.body ?? Data(), as: UTF8.self)
    for key in ["device_id", "batch_id", "source_name", "source_bundle", "uuid"] {
      XCTAssertTrue(body.contains("\"\(key)\""), "the body lacks \(key)")
    }
    XCTAssertEqual(requests.first?.contentType, "application/json")
    XCTAssertEqual(result.samplesTotal, 2500)
    XCTAssertTrue(result.pending.isEmpty)
    XCTAssertEqual(result.lastSyncAt, now)

    // A second run sends nothing new: the anchor moved on.
    let second = await sync.run(health: health, transport: transport, now: now + 60)
    let again = try await batches(transport)
    XCTAssertEqual(again.count, 2, "already-sent samples went again")
    XCTAssertEqual(second.lastSyncAt, now + 60)
  }

  func testDeletionsAreSent() async throws {
    let added: [HealthChange] = [.added(sample(1)), .added(sample(2))]
    let transport = FakeVMTransport(routes: ["POST /sync": ok, "GET /sync/status": status])
    let sync = HealthSync(state: SyncState(deviceID: "DEVICE-1"))
    _ = await sync.run(
      health: FakeHealthStore(changes: [.stepCount: added]), transport: transport, now: now)

    // Later Health holds the same two samples, then the first one's deletion.
    let gone = SyncDeletion(uuid: "SAMPLE-1", type: "HKQuantityTypeIdentifierStepCount")
    let later = FakeHealthStore(changes: [.stepCount: added + [.deleted(gone)]])
    _ = await sync.run(health: later, transport: transport, now: now + 60)
    let sent = try await batches(transport)
    XCTAssertEqual(sent.count, 2)
    XCTAssertEqual(sent.last?.deleted, [gone], "the deletion was not sent")
    XCTAssertEqual(sent.last?.samples, [], "the deleted sample was sent again")
  }

  func testFailedBatchIsRetriedNotDropped() async throws {
    // Types are read in HealthType order: steps before heart rate.
    let health = FakeHealthStore(
      changes: [.stepCount: [.added(sample(1))], .heartRate: [.added(sample(2))]])
    let transport = FakeVMTransport(
      routes: ["POST /sync": ok, "GET /sync/status": status], offline: true)
    let saved = SavedStates()
    let sync = HealthSync(state: SyncState(deviceID: "DEVICE-1"), save: saved.append)

    // No server set up yet: nothing is read or sent, and nothing shows as synced.
    let unconfigured = await sync.run(health: nil, transport: UnconfiguredVMTransport(), now: now)
    XCTAssertNil(unconfigured.lastSyncAt, "an unconfigured app shows a sync")
    XCTAssertNil(unconfigured.samplesTotal)

    // Offline: the batch stays queued on the device, saved together with the moved anchor, and
    // nothing counts as synced. The run stops there, so nothing more is read while offline.
    let offline = await sync.run(health: health, transport: transport, now: now)
    XCTAssertEqual(offline.pending.count, 1)
    XCTAssertNil(offline.lastSyncAt, "a failed sync shows as synced")
    let queued = try XCTUnwrap(saved.last, "the queue was not persisted")
    XCTAssertEqual(queued.pending.first?.samples.map(\.uuid), ["SAMPLE-1"])
    XCTAssertNotNil(queued.anchors[HealthType.stepCount.rawValue])
    XCTAssertNil(queued.anchors[HealthType.heartRate.rawValue], "read past the failure")
    let firstTry = try await batches(transport)
    XCTAssertEqual(firstTry.map(\.batchID), queued.pending.map(\.batchID))

    // A server error also keeps the batch.
    await transport.setOffline(false)
    await transport.setResponse(VMResponse(status: 503), for: "POST /sync")
    let failing = await sync.run(health: health, transport: transport, now: now)
    XCTAssertEqual(failing.pending, queued.pending)
    XCTAssertNil(failing.lastSyncAt)

    // A relaunch from the saved state, back online: the same batch goes again with the same
    // id, then the rest; the queue ends empty.
    await transport.setResponse(ok, for: "POST /sync")
    let relaunched = HealthSync(state: try XCTUnwrap(saved.last), save: saved.append)
    let online = await relaunched.run(health: health, transport: transport, now: now)
    XCTAssertTrue(online.pending.isEmpty)
    XCTAssertEqual(online.lastSyncAt, now)
    let delivered = Array(try await batches(transport).suffix(2))
    XCTAssertEqual(delivered.first?.batchID, queued.pending.first?.batchID, "a new id on retry")
    XCTAssertEqual(delivered.flatMap(\.samples).map(\.uuid), ["SAMPLE-1", "SAMPLE-2"])
  }

  /// S-029: a logged meal joins the same queue as one meal record (id, eaten-at time, day key,
  /// items with ranges and source, confirm state) and waits there while offline; an edit goes
  /// with a newer time, a delete as a tombstone with no payload, and no photo is ever sent.
  func testMealRecordCarriesRangesAndSource() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let bowl = MatchedItem(
      itemId: "01-L-000001", name: "Grain Bowl", hall: "North Hall", halls: ["North Hall"],
      brand: nil, serving: "1 bowl", servings: 1.5, confidence: 0.8, rough: false,
      kcal: FoodRange(low: 300, high: 400), proteinG: FoodRange(low: 10, high: 15))
    let side = MatchedItem(
      itemId: MatchedItem.unlistedID, name: "Side Salad", hall: nil, halls: nil, brand: nil,
      serving: nil, servings: nil, confidence: 0.4, rough: true,
      kcal: FoodRange(low: 60, high: 140), proteinG: nil)
    let id = try XCTUnwrap(UUID(uuidString: "8E2D4C6A-0000-4000-8000-000000000008"))
    var meal = LoggedMeal(id: id, loggedAt: now, items: [bowl, side])
    meal.inHealth = true
    let status = VMResponse(status: 200, body: Data(#"{"samples_total": 0}"#.utf8))
    let transport = FakeVMTransport(
      routes: ["POST /sync": ok, "GET /sync/status": status], offline: true, countsRecords: true)
    let saved = SavedStates()
    let sync = HealthSync(state: SyncState(deviceID: "DEVICE-1"), save: saved.append)

    // Offline: the record is queued and saved, not dropped.
    await sync.enqueue([.meal(meal, edited: false, at: now, calendar: calendar)])
    let offline = await sync.run(health: nil, transport: transport, now: now)
    XCTAssertEqual(offline.pending.count, 1)
    let queued = try XCTUnwrap(saved.last?.pending.first?.records?.first, "not persisted")
    XCTAssertEqual(queued.kind, "meal")
    XCTAssertNil(offline.recordsTotal)

    // Online: the same batch goes, with every field the story names.
    await transport.setOffline(false)
    let online = await sync.run(health: nil, transport: transport, now: now)
    XCTAssertTrue(online.pending.isEmpty)
    XCTAssertEqual(online.recordsTotal, 1, "the server's count does not include the meal")
    let sent = try await batches(transport)
    XCTAssertEqual(sent.count, 2, "the offline try and the resend")
    XCTAssertEqual(Set(sent.map(\.batchID)).count, 1, "a new id on retry")
    let record = try XCTUnwrap(sent.last?.records?.first)
    XCTAssertEqual(record.id, id.uuidString)
    XCTAssertFalse(record.deleted)
    XCTAssertEqual(record.updatedAt, "2027-01-15T03:00:00.000-05:00")
    let payload = try XCTUnwrap(record.payload)
    XCTAssertEqual(payload.eatenAt, "2027-01-15T03:00:00-05:00")
    XCTAssertEqual(payload.day, "2027-01-15")
    XCTAssertEqual(payload.status, "confirmed")
    XCTAssertFalse(payload.edited)
    XCTAssertEqual(payload.inHealth, true)
    XCTAssertEqual(payload.items.map(\.source), ["North Hall", "estimate"])
    XCTAssertEqual(payload.items.first?.kcal, FoodRange(low: 300, high: 400))
    XCTAssertEqual(payload.items.first?.proteinG, FoodRange(low: 10, high: 15))
    XCTAssertEqual(payload.items.first?.servings, 1.5)
    XCTAssertEqual(payload.items.last?.rough, true)
    XCTAssertNil(payload.items.last?.proteinG, "a missing range became a number")
    let requests = await transport.sent.filter { $0.route == "POST /sync" }
    let body = String(decoding: requests.last?.body ?? Data(), as: UTF8.self)
    for key in ["records", "updated_at", "eaten_at", "item_id", "protein_g", "in_health"] {
      XCTAssertTrue(body.contains("\"\(key)\""), "the body lacks \(key)")
    }
    XCTAssertFalse(body.contains("photo") || body.contains("image"), "a photo went again")

    // An edit is newer; a delete is a tombstone without a payload.
    let edited = LoggedMeal(id: id, loggedAt: now, items: [bowl])
    await sync.enqueue([.meal(edited, edited: true, at: now + 0.25, calendar: calendar)])
    await sync.enqueue([.deletedMeal(id, at: now + 0.5, calendar: calendar)])
    let after = await sync.run(health: nil, transport: transport, now: now + 1)
    let last = try await batches(transport).suffix(2).compactMap { $0.records?.first }
    XCTAssertEqual(last.map(\.payload?.edited), [true, nil])
    XCTAssertEqual(last.map(\.deleted), [false, true])
    XCTAssertLessThan(record.updatedAt, last[0].updatedAt, "the edit is not newer")
    XCTAssertLessThan(last[0].updatedAt, last[1].updatedAt, "the delete is not newer")
    XCTAssertEqual(after.recordsTotal, 0, "the tombstone still counts as a meal")
  }
}
