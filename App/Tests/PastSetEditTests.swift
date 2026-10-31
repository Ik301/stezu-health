import StezuCore
import XCTest

@testable import StezuHealth

/// S-055: a set edited after the fact is saved in finished-workouts.json first, then its record
/// and the session's join the sync queue. Made-up numbers (D-034).
final class PastSetEditTests: XCTestCase {
  func testEditSavesOnPhoneThenQueuesRecords() async throws {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    var environment = AppEnvironment.fakes(offline: true)
    environment.storage = .temporary(folder)
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var session = WorkoutSession(startedAt: start, templateKey: "day-1")
    session.logSet("Bench press", pounds: 20, reps: 8, at: start + 60)
    session.logSet("Bench press", pounds: 60, reps: 8, at: start + 180)
    let done = try XCTUnwrap(WorkoutFinish.close(session, at: start + 600))
    let store = FinishedWorkoutStore(storage: environment.storage)
    store.save([done])
    let demo = try XCTUnwrap(session.sets(for: "Bench press")?.first)
    let past = PastSet(sessionStart: start, exercise: "Bench press", number: 1, set: demo)

    let saved = await environment.editSet(.delete, past, in: store.load())
    XCTAssertEqual(store.load(), saved, "the edit is not saved on the phone")
    XCTAssertEqual(saved.first?.session.sets(for: "Bench press")?.map(\.pounds), [60])
    let queued = await environment.healthSync.state.pending.compactMap(\.records).flatMap { $0 }
    XCTAssertEqual(queued.map(\.kind), ["set", "workout_session"])
    XCTAssertEqual(queued.first?.id, WorkoutRecords.setID(demo, in: session))
    XCTAssertEqual(queued.first?.deleted, true)
    XCTAssertEqual(queued.last?.id, done.externalID)
    XCTAssertEqual(queued.last?.sessionPayload?.exercises.first?.sets.count, 1)

    // A set that is not there changes nothing and queues nothing.
    let again = await environment.editSet(.delete, past, in: saved)
    XCTAssertEqual(again, saved)
    let after = await environment.healthSync.state.pending.compactMap(\.records).flatMap { $0 }
    XCTAssertEqual(after.count, 2)
  }
}
