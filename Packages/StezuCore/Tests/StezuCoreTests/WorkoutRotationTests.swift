import Foundation
import StezuCore
import XCTest

// S-036, D-089 and D-090. Generic days and numbers, not anyone's program (D-034).
final class WorkoutRotationTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)

  private func day(_ n: Int) -> WorkoutTemplate {
    WorkoutTemplate(
      key: "day-\(n)", name: "Day \(n)",
      exercises: [
        TemplateExercise(
          key: "lift-\(n)", name: "Lift \(n)", sets: 3, repsLow: 6, repsHigh: 10, restSeconds: 90,
          startPounds: 45)
      ])
  }

  private func library(_ days: Int...) -> TemplateLibrary {
    var library = TemplateLibrary()
    library.replaceProgram(with: days.map(day))
    return library
  }

  /// A session of `key` started at `start + startHours`, with one set, ended an hour later.
  private func finished(_ key: String?, startHours: Double) -> FinishedWorkout {
    let begin = start + startHours * 3600
    var session = WorkoutSession(startedAt: begin, templateKey: key)
    session.logSet("Lift", pounds: 50, reps: 8, at: begin + 60)
    return FinishedWorkout(
      session: session, endedAt: begin + 3600, externalID: WorkoutFinish.externalID(for: session),
      inHealth: true)
  }

  func testNextFollowsMostRecentFinishedSession() {
    let program = library(1, 2, 3)
    XCTAssertEqual(WorkoutRotation.next(in: program, finished: [])?.key, "day-1", "none finished")

    // Day 1 then Day 2: the one that ended last decides, whatever the list order.
    let sessions = [finished("day-2", startHours: 24), finished("day-1", startHours: 0)]
    XCTAssertEqual(WorkoutRotation.next(in: program, finished: sessions)?.key, "day-3")

    // By order, never by date: a week off does not skip a day; the last day wraps to the first.
    let late = sessions + [finished("day-3", startHours: 24 * 9)]
    XCTAssertEqual(WorkoutRotation.next(in: program, finished: late)?.key, "day-1")

    // An Empty workout is not a day and leaves the rotation where it was.
    let empty = sessions + [finished(WorkoutRotation.emptyKey, startHours: 48)]
    XCTAssertEqual(WorkoutRotation.next(in: program, finished: empty)?.key, "day-3")

    // The last template is no longer in the program: the first day.
    let removed = sessions + [finished("old-day", startHours: 48)]
    XCTAssertEqual(WorkoutRotation.next(in: program, finished: removed)?.key, "day-1")
  }

  func testOffScheduleSessionMovesRotation() {
    let program = library(1, 2, 3, 4)
    var sessions = [finished("day-1", startHours: 0)]
    XCTAssertEqual(WorkoutRotation.next(in: program, finished: sessions)?.key, "day-2")

    // Day 3 started off schedule instead of Day 2: the program is unchanged and Next follows it.
    sessions.append(finished("day-3", startHours: 24))
    XCTAssertEqual(WorkoutRotation.next(in: program, finished: sessions)?.key, "day-4")
    XCTAssertEqual(program.days.map(\.key), ["day-1", "day-2", "day-3", "day-4"])
  }

  func testContinueWindowIsTwelveHours() {
    let program = library(1, 2)
    let workout = finished("day-1", startHours: 0)
    let at = { (hours: Double) in self.start + hours * 3600 }
    XCTAssertTrue(WorkoutRotation.canContinue(workout, library: program, now: at(1)))
    XCTAssertTrue(WorkoutRotation.canContinue(workout, library: program, now: at(11.99)))
    XCTAssertFalse(WorkoutRotation.canContinue(workout, library: program, now: at(12)))
    XCTAssertFalse(WorkoutRotation.canContinue(workout, library: program, now: at(30)))

    // The row offers the newest one still inside the window; older sessions offer none.
    let older = finished("day-2", startHours: -20)
    let row = WorkoutRotation.continuable([older, workout], library: program, now: at(2))
    XCTAssertEqual(row?.externalID, workout.externalID)
    XCTAssertNil(WorkoutRotation.continuable([older], library: program, now: at(2)))

    // A session whose template was removed, or an Empty workout, cannot be continued.
    let gone = finished("old-day", startHours: 0)
    XCTAssertFalse(WorkoutRotation.canContinue(gone, library: program, now: at(1)))
    let empty = finished(WorkoutRotation.emptyKey, startHours: 0)
    XCTAssertFalse(WorkoutRotation.canContinue(empty, library: program, now: at(1)))
  }

  func testContinuedSessionKeepsIdAndAppendsSets() async throws {
    let program = library(1, 2)
    var session = WorkoutSession(startedAt: start, templateKey: "day-1")
    session.logSet("Lift 1", pounds: 55, reps: 7, at: start + 60)
    let first = try XCTUnwrap(WorkoutFinish.close(session, at: start + 600))
    let health = FakeHealthStore()
    var original = first
    original.inHealth = await WorkoutFinish.write(first, to: health)
    let others = [finished("day-2", startHours: -48), original]

    // Continue: the same session, its set shown, the card prefilled from that set.
    var logger = try XCTUnwrap(WorkoutRotation.reopen(original, library: program, history: []))
    XCTAssertEqual(logger.session, session)
    XCTAssertEqual(logger.loggedSets.count, 1)
    XCTAssertEqual(logger.setNumber, 2)
    XCTAssertEqual(logger.pounds, 55)
    XCTAssertEqual(logger.reps, 7)
    XCTAssertFalse(logger.canUndo, "a set from before the Continue can be undone")
    XCTAssertNotNil(logger.log(at: start + 3600))
    XCTAssertEqual(logger.session.sets(for: "Lift 1")?.count, 2)

    // Finish saves it under the same id, replacing the first copy instead of adding one.
    let again = try XCTUnwrap(WorkoutFinish.close(logger.session, at: start + 3700))
    XCTAssertEqual(again.externalID, original.externalID)
    XCTAssertEqual(
      WorkoutRecords.setID(session.exercises[0].sets[0], in: logger.session),
      WorkoutRecords.setID(session.exercises[0].sets[0], in: session))
    let kept = WorkoutRotation.keep(again, in: others)
    XCTAssertEqual(kept.count, 2)
    XCTAssertEqual(kept[1].workingSets, 2)
    XCTAssertEqual(kept[1].endedAt, start + 3700)

    // Health: the old workout is deleted by id and one new one is written to the new end.
    let replaced = await WorkoutFinish.write(again, to: health, replacing: original.inHealth)
    XCTAssertTrue(replaced)
    let saved = await health.savedWorkouts
    XCTAssertEqual(
      saved, [SavedWorkout(start: start, end: start + 3700, externalID: original.externalID)])

    // The session record goes again with the same id and a newer updated_at.
    let before = SyncRecord.session(original, templateName: "Day 1", keys: [:], at: start + 600)
    let after = SyncRecord.session(again, templateName: "Day 1", keys: [:], at: start + 3700)
    XCTAssertEqual(after.id, before.id)
    XCTAssertGreaterThan(after.updatedAt, before.updatedAt)
  }
}
