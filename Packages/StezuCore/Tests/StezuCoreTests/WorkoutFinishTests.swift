import StezuCore
import XCTest

final class WorkoutFinishTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)

  private func oneSetSession() -> WorkoutSession {
    var session = WorkoutSession(startedAt: start, templateKey: "day-a")
    session.logSet("Exercise A", pounds: 50, reps: 8, at: start + 60)
    return session
  }

  func testFinishWritesOneWorkoutWithExternalID() async throws {
    let health = FakeHealthStore()
    let session = oneSetSession()
    let finished = await WorkoutFinish.finish(session, at: start + 1800, health: health)
    let done = try XCTUnwrap(finished)
    XCTAssertTrue(done.inHealth)
    XCTAssertEqual(done.session, session)
    XCTAssertEqual(done.workingSets, 1)
    XCTAssertEqual(done.externalID, WorkoutFinish.externalID(for: session))

    // A retry of the same session reuses the id and writes nothing new.
    let retry = await WorkoutFinish.finish(session, at: start + 1900, health: health)
    XCTAssertEqual(retry?.externalID, done.externalID)
    let saved = await health.savedWorkouts
    XCTAssertEqual(
      saved, [SavedWorkout(start: start, end: start + 1800, externalID: done.externalID)])
  }

  func testEmptySessionIsDiscarded() async {
    let health = FakeHealthStore()
    var session = oneSetSession()
    session.removeLastSet(of: "Exercise A")
    let finished = await WorkoutFinish.finish(session, at: start + 600, health: health)
    XCTAssertNil(finished)
    let empty = await WorkoutFinish.finish(
      WorkoutSession(startedAt: start), at: start + 600, health: health)
    XCTAssertNil(empty)
    let saved = await health.savedWorkouts
    XCTAssertTrue(saved.isEmpty, "an empty workout was written")
  }

  func testFailedWriteKeepsSession() async throws {
    let health = FakeHealthStore()
    await health.setFailsWrites(true)
    let session = oneSetSession()
    let finished = await WorkoutFinish.finish(session, at: start + 1800, health: health)
    let done = try XCTUnwrap(finished, "a failed write dropped the session")
    XCTAssertFalse(done.inHealth)
    XCTAssertEqual(done.session, session)
    let saved = await health.savedWorkouts
    XCTAssertTrue(saved.isEmpty)

    // The week holds it; a session from the week before does not count.
    let older = FinishedWorkout(
      session: WorkoutSession(startedAt: start - 8 * 86_400), endedAt: start - 8 * 86_400,
      externalID: "older", inHealth: true)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let week = WorkoutFinish.week(containing: start + 1800, in: [older, done], calendar: calendar)
    XCTAssertEqual(week, [done])
  }
}
