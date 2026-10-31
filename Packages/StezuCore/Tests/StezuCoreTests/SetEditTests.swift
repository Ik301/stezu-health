import Foundation
import XCTest

@testable import StezuCore

/// S-055: a set of a finished session is changed or deleted after the fact. The set keeps its id,
/// and the session is re-sent under its id, both newer. Every number is made up (D-034).
final class SetEditTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)

  private func workout() throws -> FinishedWorkout {
    var session = WorkoutSession(startedAt: start, templateKey: "day-1")
    session.logSet("Bench press", pounds: 20, reps: 8, at: start + 60)
    session.logSet("Bench press", pounds: 60, reps: 8, at: start + 180)
    session.logSet("Dip", pounds: nil, reps: 10, at: start + 300)
    return try XCTUnwrap(WorkoutFinish.close(session, at: start + 900))
  }

  /// A change keeps the set's time and id; the set record is sent again, newer, with the new
  /// numbers, and so is the session, whose sets now hold them.
  func testChangeKeepsSetIdAndResendsSession() throws {
    let before = try workout()
    let logged = SyncRecord.set(
      before.session.exercises[0].sets[1], exercise: "Bench press", key: "bench",
      in: before.session, at: start + 181)
    let (after, records) = try XCTUnwrap(
      before.applying(
        .change(pounds: 65, reps: 6), toSetAt: start + 180, templateName: "Day 1",
        keys: ["Bench press": "bench"], at: start + 86_400))

    XCTAssertEqual(after.session.sets(for: "Bench press")?.map(\.pounds), [20, 65])
    XCTAssertEqual(after.session.sets(for: "Bench press")?.map(\.reps), [8, 6])
    XCTAssertEqual(after.externalID, before.externalID)
    XCTAssertEqual(after.endedAt, before.endedAt)
    XCTAssertEqual(records.map(\.kind), ["set", "workout_session"])
    let set = records[0]
    XCTAssertEqual(set.id, logged.id, "the edited set got another id")
    XCTAssertFalse(set.deleted)
    XCTAssertLessThan(logged.updatedAt, set.updatedAt, "the edit is not newer")
    XCTAssertEqual(set.setPayload?.pounds, 65)
    XCTAssertEqual(set.setPayload?.reps, 6)
    XCTAssertEqual(set.setPayload?.exerciseKey, "bench")
    let session = records[1]
    XCTAssertEqual(session.id, before.externalID)
    XCTAssertEqual(session.updatedAt, set.updatedAt)
    XCTAssertEqual(session.sessionPayload?.exercises[0].sets.map(\.reps), [8, 6])

    // Not a real set, or no such set: nothing changes and nothing is sent.
    XCTAssertNil(
      before.applying(
        .change(pounds: 0, reps: 6), toSetAt: start + 180, templateName: nil, keys: [:],
        at: start + 86_400))
    XCTAssertNil(
      before.applying(.delete, toSetAt: start + 1, templateName: nil, keys: [:], at: start))
  }

  /// Delete sends the set's id as a tombstone (as Undo does) and the session without it; an
  /// exercise with no sets left is dropped.
  func testDeleteSendsTombstoneAndSessionWithoutTheSet() throws {
    let before = try workout()
    let id = WorkoutRecords.setID(before.session.exercises[0].sets[0], in: before.session)
    let (after, records) = try XCTUnwrap(
      before.applying(
        .delete, toSetAt: start + 60, templateName: "Day 1", keys: [:], at: start + 86_400))
    XCTAssertEqual(after.session.sets(for: "Bench press")?.map(\.pounds), [60])
    XCTAssertEqual(after.workingSets, 2)
    XCTAssertEqual(records[0].id, id)
    XCTAssertTrue(records[0].deleted)
    XCTAssertNil(records[0].setPayload)
    let sets = records[1].sessionPayload?.exercises.flatMap(\.sets).map(\.id) ?? []
    XCTAssertEqual(sets.count, 2)
    XCTAssertFalse(sets.contains(id), "the deleted set is still in the session")

    let (noDip, _) = try XCTUnwrap(
      after.applying(.delete, toSetAt: start + 300, templateName: nil, keys: [:], at: start))
    XCTAssertEqual(noDip.session.exercises.map(\.exercise), ["Bench press"])
  }

  /// The last set deleted leaves the session, with no sets, under its id; it is sent empty.
  func testDeletingLastSetKeepsEmptySession() throws {
    var session = WorkoutSession(startedAt: start)
    session.logSet("Row", pounds: 50, reps: 10, at: start + 60)
    let one = try XCTUnwrap(WorkoutFinish.close(session, at: start + 600))
    let (after, records) = try XCTUnwrap(
      one.applying(.delete, toSetAt: start + 60, templateName: nil, keys: [:], at: start + 700))
    XCTAssertEqual(after.workingSets, 0)
    XCTAssertEqual(after.externalID, one.externalID)
    XCTAssertEqual(records.last?.kind, "workout_session")
    XCTAssertFalse(records.last?.deleted ?? true, "the session was deleted")
    XCTAssertEqual(records.last?.sessionPayload?.exercises.count, 0)
  }
}
