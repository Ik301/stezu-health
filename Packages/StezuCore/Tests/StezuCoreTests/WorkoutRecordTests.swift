import Foundation
import XCTest

@testable import StezuCore

/// S-030: logged sets and finished sessions become `/sync` records on the meal queue. Every
/// number is made up (D-034).
final class WorkoutRecordTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)
  private let template = WorkoutTemplate(
    key: "day-1", name: "Day 1",
    exercises: [
      TemplateExercise(
        key: "bench", name: "Bench press", sets: 2, repsLow: 8, repsHigh: 10, restSeconds: 90,
        startPounds: 45),
      TemplateExercise(key: "dip", name: "Dip", sets: 1, repsLow: 8, repsHigh: 12, restSeconds: 60),
    ])

  private func payload(_ record: SyncRecord) throws -> [String: Any] {
    let body = try JSONEncoder().encode(record)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    return try XCTUnwrap(object["payload"] as? [String: Any], "no payload")
  }

  /// A logged set carries its id, session, template, exercise key and name, pounds, reps, time
  /// and kind; a bodyweight set sends null pounds, never 0; the record survives a reload.
  func testSetRecordCarriesSessionAndExercise() throws {
    var logger = SetLogger(template: template, startedAt: start)
    let set = try XCTUnwrap(logger.log(at: start + 60))
    let record = SyncRecord.set(
      set, exercise: "Bench press", key: "bench", in: logger.session, at: start + 61)
    XCTAssertEqual(record.kind, "set")
    XCTAssertFalse(record.deleted)
    let sessionID = WorkoutFinish.externalID(for: logger.session)
    XCTAssertEqual(record.id, "\(sessionID).set.1800000060000")
    let body = try payload(record)
    XCTAssertEqual(body["id"] as? String, record.id)
    XCTAssertEqual(body["session_id"] as? String, sessionID)
    XCTAssertEqual(body["template_key"] as? String, "day-1")
    XCTAssertEqual(body["exercise_key"] as? String, "bench")
    XCTAssertEqual(body["exercise"] as? String, "Bench press")
    XCTAssertEqual(body["reps"] as? Int, 8)
    XCTAssertEqual(body["kind"] as? String, "working")
    XCTAssertNotNil(body["logged_at"] as? String)
    XCTAssertEqual(body["pounds"] as? Double, 45)

    // A bodyweight set: pounds is present and null, not 0.
    logger.toggleBodyweight()
    let bodyweight = try XCTUnwrap(logger.log(at: start + 120))
    let bwRecord = SyncRecord.set(
      bodyweight, exercise: "Bench press", key: "bench", in: logger.session, at: start + 121)
    let bwBody = try payload(bwRecord)
    XCTAssertTrue(bwBody.keys.contains("pounds"), "pounds left out")
    XCTAssertTrue(
      bwBody["pounds"] is NSNull, "bodyweight became \(String(describing: bwBody["pounds"]))")

    // Weighted, and it decodes back as a set record (sync-state.json reloads it).
    let weighted = WorkoutSet(pounds: 95, reps: 6, loggedAt: start + 180)
    let saved = SyncRecord.set(
      weighted, exercise: "Dip", key: nil, in: logger.session, at: start + 181)
    XCTAssertEqual(try payload(saved)["pounds"] as? Double, 95)
    let reloaded = try JSONDecoder().decode(SyncRecord.self, from: JSONEncoder().encode(saved))
    XCTAssertEqual(reloaded, saved)
    XCTAssertEqual(reloaded.setPayload?.exercise, "Dip")
    XCTAssertNil(reloaded.payload, "a set decoded as a meal")
  }

  /// Undo queues the same set id as a tombstone, newer even within the same second.
  func testUndoQueuesDeletedSet() async throws {
    var logger = SetLogger(template: template, startedAt: start)
    let set = try XCTUnwrap(logger.log(at: start + 60))
    let logged = SyncRecord.set(
      set, exercise: "Bench press", key: "bench", in: logger.session, at: start + 60.1)
    let undone = try XCTUnwrap(logger.undo())
    let tombstone = SyncRecord.deletedSet(undone, in: logger.session, at: start + 60.4)
    XCTAssertEqual(tombstone.kind, "set")
    XCTAssertEqual(tombstone.id, logged.id, "undo sent another id")
    XCTAssertTrue(tombstone.deleted)
    XCTAssertNil(tombstone.setPayload)
    XCTAssertNotEqual(logged.updatedAt, tombstone.updatedAt, "two versions in one second collide")
    XCTAssertLessThan(logged.updatedAt, tombstone.updatedAt)

    let transport = FakeVMTransport(
      routes: [
        "POST /sync": VMResponse(status: 200, body: Data("{}".utf8)),
        "GET /sync/status": VMResponse(status: 200, body: Data(#"{"samples_total": 0}"#.utf8)),
      ], countsRecords: true)
    let sync = HealthSync(state: SyncState(deviceID: "DEVICE-1"))
    await sync.enqueue([logged])
    await sync.enqueue([tombstone])
    let state = await sync.run(health: nil, transport: transport, now: start + 61)
    XCTAssertTrue(state.pending.isEmpty)
    XCTAssertEqual(state.recordsTotal, 0, "the undone set still counts")
    let body = String(
      decoding: await transport.sent.last { $0.route == "POST /sync" }?.body ?? Data(),
      as: UTF8.self)
    XCTAssertFalse(body.contains("\"payload\""), "a tombstone carries a payload: \(body)")
  }

  /// The first launch queues every finished session (with swaps and custom exercises by key
  /// and name) and the unfinished logger's sets as one batch; a flag stops a second backfill,
  /// also after a reload of the saved state.
  func testBackfillQueuesFinishedSessionsOnce() async throws {
    var first = WorkoutSession(startedAt: start, templateKey: "day-1")
    first.logSet("Bench press", pounds: 60, reps: 8, at: start + 60)
    first.logSet("Ring row", pounds: nil, reps: 10, at: start + 120)  // a custom swap
    let done = try XCTUnwrap(WorkoutFinish.close(first, at: start + 600))
    XCTAssertFalse(done.inHealth, "closed as in Health before any write")
    var active = WorkoutSession(startedAt: start + 86_400, templateKey: "day-1")
    active.logSet("Bench press", pounds: 65, reps: 6, at: start + 86_460)
    let keys = ["Bench press": "bench", "Ring row": "custom-ring-row"]
    let records =
      WorkoutRecords.backfill(
        finished: [done], active: active, templates: ["day-1": "Day 1"], keys: keys,
        at: start + 90_000)

    let saved = LockedStates()
    let sync = HealthSync(state: SyncState(deviceID: "DEVICE-1"), save: saved.append)
    await sync.backfillWorkouts(records)
    await sync.backfillWorkouts(records)
    let state = await sync.state
    XCTAssertEqual(state.workoutsBackfilled, true)
    XCTAssertEqual(state.pending.count, 1, "backfilled twice")
    let queued = state.pending.first?.records ?? []
    XCTAssertEqual(queued.map(\.kind), ["workout_session", "set"])
    let session = try XCTUnwrap(queued.first?.sessionPayload)
    XCTAssertEqual(session.id, done.externalID)
    XCTAssertEqual(session.templateKey, "day-1")
    XCTAssertEqual(session.templateName, "Day 1")
    XCTAssertEqual(session.exercises.map(\.key), ["bench", "custom-ring-row"])
    XCTAssertEqual(session.exercises.map(\.name), ["Bench press", "Ring row"])
    XCTAssertEqual(session.exercises.last?.sets.first?.pounds, nil)
    XCTAssertEqual(session.exercises.first?.sets.first?.pounds, 60)
    let body = try payload(try XCTUnwrap(queued.first))
    for key in ["template_key", "template_name", "start", "end", "exercises"] {
      XCTAssertNotNil(body[key], "the session lacks \(key)")
    }
    XCTAssertEqual(queued.last?.setPayload?.sessionId, WorkoutFinish.externalID(for: active))

    // Relaunch from the saved state: the flag holds, nothing is queued again.
    let reloaded = try JSONDecoder().decode(
      SyncState.self, from: JSONEncoder().encode(try XCTUnwrap(saved.last)))
    let again = HealthSync(state: reloaded)
    await again.backfillWorkouts(records)
    let after = await again.state
    XCTAssertEqual(after.pending.count, 1)
  }
}

private final class LockedStates: @unchecked Sendable {
  private let lock = NSLock()
  private var states: [SyncState] = []
  var last: SyncState? { lock.withLock { states.last } }
  func append(_ state: SyncState) { lock.withLock { states.append(state) } }
}
