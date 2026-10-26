import Foundation
import XCTest

@testable import StezuCore

/// S-031: the phone's weigh-in file comes first, Health is a copy, and every change is queued as
/// a `weigh_in` record. Every number is made up (D-034).
final class WeighInStoreTests: XCTestCase {
  /// Collects what the store saves and queues.
  private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _saves: [WeighInLog] = []
    private var _records: [SyncRecord] = []
    var saves: [WeighInLog] { lock.withLock { _saves } }
    var records: [SyncRecord] { lock.withLock { _records } }
    func saved(_ log: WeighInLog) { lock.withLock { _saves.append(log) } }
    func queued(_ records: [SyncRecord]) { lock.withLock { _records += records } }
  }

  private func payload(_ record: SyncRecord) throws -> [String: Any] {
    let body = try JSONEncoder().encode(record)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(object["kind"] as? String, "weigh_in")
    return try XCTUnwrap(object["payload"] as? [String: Any], "no payload")
  }

  /// The first save holds the weigh-in before Health was tried (in_health still nil); Health then
  /// has the sample tagged with its id, and the queued record says Health took it. A failed
  /// Health write keeps the weigh-in, saved and queued with in_health false.
  func testLocalSaveComesBeforeHealthAndSync() async throws {
    let recorder = Recorder()
    let health = FakeHealthStore()
    let store = WeighInStore(save: recorder.saved)
    let sync: WeighInStore.Sync = { records in
      // By the time the record is queued, Health already has the sample.
      let inHealth = await health.storedSamples.contains { $0.id == records.first?.id }
      XCTAssertTrue(inHealth, "the record was queued before the Health write")
      recorder.queued(records)
    }
    let at = WeightFixture.day(6, hour: 7)
    let weighIn = await store.add(pounds: 170.04, at: at, id: "W1", health: health, sync: sync)

    let first = try XCTUnwrap(recorder.saves.first)
    XCTAssertEqual(first.weighIns.map(\.id), ["W1"], "the first save is the weigh-in")
    XCTAssertNil(first.weighIns[0].inHealth, "saved after Health was tried, not before")
    XCTAssertEqual(recorder.saves.last?.weighIns.first?.inHealth, true)
    XCTAssertEqual(weighIn.pounds, 170.0)
    let samples = await health.storedSamples
    XCTAssertEqual(samples.map(\.id), ["W1"])
    XCTAssertEqual(samples.first?.value, 170.0)
    XCTAssertEqual(recorder.records.count, 1)
    let record = try XCTUnwrap(recorder.records.first)
    XCTAssertFalse(record.deleted)
    let sent = try payload(record)
    XCTAssertEqual(sent["id"] as? String, "W1")
    XCTAssertEqual(sent["pounds"] as? Double, 170.0)
    XCTAssertEqual(sent["in_health"] as? Bool, true)
    XCTAssertNotNil(sent["measured_at"] as? String)

    // Denied: the weigh-in stays, is queued, and shows as not in Health.
    let denied = FakeHealthStore()
    await denied.setFailsWrites(true)
    let kept = await store.add(
      pounds: 169.5, at: at + 86_400, id: "W2", health: denied, sync: { recorder.queued($0) })
    XCTAssertEqual(kept.inHealth, false)
    let log = await store.log
    XCTAssertEqual(log.weighIns.map(\.id), ["W1", "W2"])
    XCTAssertEqual(recorder.saves.last, log, "the refusal is saved")
    let notInHealth = await store.notInHealth()
    XCTAssertEqual(notInHealth.map(\.id), ["W2"])
    XCTAssertEqual(try payload(try XCTUnwrap(recorder.records.last))["in_health"] as? Bool, false)
    let read = await store.samples()
    XCTAssertEqual(read.map(\.value), [170.0, 169.5])
    XCTAssertEqual(Set(read.map(\.sourceBundleID)), [WeeklyWeight.stezuBundleID])
  }

  /// Stezu's body-mass samples already in Health join the file once, matched by Health UUID so a
  /// weigh-in already in the file is not doubled; a strap's are left out. The weight screens read
  /// the file, never Health's Stezu samples, and never a strap's weight as a weigh-in.
  func testMigrationImportsStezuHealthSamplesOnce() async throws {
    let health = FakeHealthStore(samples: [
      HealthSample(
        type: .bodyMass, date: WeightFixture.day(5), sourceName: "Stezu",
        sourceBundleID: WeeklyWeight.stezuBundleID, value: 171.0, id: "H1"),
      HealthSample(
        type: .bodyMass, date: WeightFixture.day(6), sourceName: "Stezu",
        sourceBundleID: WeeklyWeight.stezuBundleID, value: 170.8, id: "H2"),
      HealthSample(
        type: .bodyMass, date: WeightFixture.day(7), sourceName: "Strap",
        sourceBundleID: "example.strap", value: 150.0, id: "S1"),
    ])
    var log = WeighInLog()
    log.weighIns = [StoredWeighIn(id: "H1", measuredAt: WeightFixture.day(5), pounds: 171.0)]
    let recorder = Recorder()
    let store = WeighInStore(log: log, save: recorder.saved)

    await store.migrate(from: health, sync: { recorder.queued($0) })
    let after = await store.log
    XCTAssertTrue(after.migrated)
    XCTAssertEqual(after.weighIns.map(\.id), ["H1", "H2"], "H1 doubled or the strap imported")
    XCTAssertEqual(after.weighIns.last?.inHealth, true)
    XCTAssertEqual(recorder.records.map(\.id), ["H2"])
    XCTAssertEqual(recorder.saves.last, after)

    // Once per install: a second run changes nothing and queues nothing.
    await store.migrate(from: health, sync: { recorder.queued($0) })
    let again = await store.log
    XCTAssertEqual(again, after)
    XCTAssertEqual(recorder.records.count, 1)

    // The weight screens read the file plus other apps; the trend leaves the strap out.
    let read = WeighInHealth(base: health, store: store, migrates: true) { _ in }
    let samples = try await read.samples(of: .bodyMass, since: WeightFixture.day(1))
    XCTAssertEqual(samples.map(\.id), ["H1", "H2", "S1"])
    let week = WeeklyWeight.week(
      of: samples, now: WeightFixture.now, calendar: WeightFixture.calendar)
    XCTAssertEqual(week.daysWeighed, 2)
    XCTAssertEqual(week.sources, ["Stezu"])
  }

  /// Delete removes the weigh-in from the file first, then Health's sample by its id, then
  /// queues the same id with deleted: true and no payload. A failed Health delete still deletes.
  func testDeleteQueuesTombstone() async throws {
    let health = FakeHealthStore()
    let recorder = Recorder()
    let store = WeighInStore(save: recorder.saved)
    let at = WeightFixture.day(8, hour: 7)
    await store.add(pounds: 170.2, at: at, id: "W1", health: health, sync: { recorder.queued($0) })
    await store.add(
      pounds: 170.0, at: at + 86_400, id: "W2", health: health, sync: { recorder.queued($0) })

    let saves = recorder.saves.count
    await store.delete(at: at, health: health) { records in
      XCTAssertEqual(recorder.saves.count, saves + 1, "queued before the local save")
      XCTAssertEqual(recorder.saves.last?.weighIns.map(\.id), ["W2"])
      recorder.queued(records)
    }
    let samples = await health.storedSamples
    XCTAssertEqual(samples.map(\.id), ["W2"], "Health still has the deleted weigh-in")
    let tombstone = try XCTUnwrap(recorder.records.last)
    XCTAssertEqual(tombstone.kind, "weigh_in")
    XCTAssertEqual(tombstone.id, "W1")
    XCTAssertTrue(tombstone.deleted)
    let body = try JSONEncoder().encode(tombstone)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertNil(object["payload"], "a tombstone has no payload")
    XCTAssertEqual(object["deleted"] as? Bool, true)

    // Health refuses: the weigh-in still leaves the phone and the tombstone is still queued.
    await health.setFailsWrites(true)
    await store.delete(at: at + 86_400, health: health, sync: { recorder.queued($0) })
    let log = await store.log
    XCTAssertTrue(log.weighIns.isEmpty)
    XCTAssertEqual(recorder.records.filter(\.deleted).map(\.id), ["W1", "W2"])
  }
}
