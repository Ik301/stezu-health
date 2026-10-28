import Foundation
import StezuCore
import XCTest

// S-044, D-111. Generic days and numbers, not anyone's program (D-034).
final class WorkoutSummaryTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)

  private let push = WorkoutTemplate(
    key: "push", name: "Push",
    exercises: [
      TemplateExercise(
        key: "press", name: "Press", sets: 2, repsLow: 6, repsHigh: 10, restSeconds: 90,
        startPounds: 45),
      TemplateExercise(
        key: "dip", name: "Dip", sets: 2, repsLow: 8, repsHigh: 12, restSeconds: 60),
      TemplateExercise(
        key: "fly", name: "Fly", sets: 2, repsLow: 10, repsHigh: 15, restSeconds: 60,
        startPounds: 20),
    ])

  /// A past session of `key`, `daysAgo` before `start`, with these (exercise, pounds, reps).
  private func past(_ key: String, daysAgo: Double, _ sets: [(String, Double?, Int)])
    -> WorkoutSession
  {
    let begin = start - daysAgo * 86_400
    var session = WorkoutSession(startedAt: begin, templateKey: key)
    for (index, set) in sets.enumerated() {
      session.logSet(set.0, pounds: set.1, reps: set.2, at: begin + Double(index + 1) * 60)
    }
    return session
  }

  func testBestSetComparisonWithLastSessionOfTemplate() throws {
    // Push 7 days ago, Push 14 days ago, and a newer Other session that also pressed.
    let history = [
      past("push", daysAgo: 14, [("Press", 40, 8)]),
      past("push", daysAgo: 7, [("Press", 50, 8), ("Press", 55, 6), ("Dip", nil, 10)]),
      past("other", daysAgo: 2, [("Press", 70, 3)]),
    ]
    var logger = SetLogger(template: push, startedAt: start, history: history)
    XCTAssertEqual(logger.pounds, 50, "prefilled from the last Push")
    logger.stepWeight(up: true)
    logger.stepWeight(up: true)
    logger.log(at: start + 60)  // 60 x 8
    logger.stepWeight(up: false)
    logger.log(at: start + 120)  // 55 x 8
    XCTAssertEqual(logger.exercise?.name, "Dip")
    logger.stepReps(up: false)
    logger.log(at: start + 180)  // BW x 9
    logger.log(at: start + 200)  // BW x 9
    XCTAssertEqual(logger.exercise?.name, "Fly", "never done before")
    logger.log(at: start + 240)  // 20 x 10

    let summary = try XCTUnwrap(
      WorkoutSummary(logger: logger, endedAt: start + 1800, history: history))
    XCTAssertEqual(summary.lastSessionAt, start - 7 * 86_400, "the last Push, not Other")
    XCTAssertEqual(summary.exercises.map(\.exercise), ["Press", "Dip", "Fly"])
    // Best press 60 x 8 against last Push's best 55 x 6 (not Other's 70 x 3): a weight change.
    let best = try XCTUnwrap(WorkoutSummary.best(logger.session.sets(for: "Press") ?? []))
    XCTAssertEqual(best.pounds, 60, "the heaviest set")
    XCTAssertEqual(summary.exercises[0].change, "+5 lb")
    XCTAssertEqual(summary.exercises[1].change, "-1 rep", "bodyweight compares reps")
    XCTAssertNil(summary.exercises[2].change, "nothing to compare is absent, not same")
    XCTAssertEqual(summary.done.endedAt, start + 1800)
    XCTAssertEqual(summary.done.workingSets, 5)

    XCTAssertEqual(
      WorkoutSummary.change(
        WorkoutSet(pounds: 50, reps: 8, loggedAt: start), from: best),
      "-10 lb")
    XCTAssertEqual(
      WorkoutSummary.change(
        WorkoutSet(pounds: 60, reps: 8, loggedAt: start), from: best),
      "same")
    XCTAssertEqual(
      WorkoutSummary.change(
        WorkoutSet(pounds: 60, reps: 10, loggedAt: start), from: best),
      "+2 reps")
    XCTAssertNil(
      WorkoutSummary.change(
        WorkoutSet(pounds: nil, reps: 10, loggedAt: start), from: best),
      "bodyweight against a weighted set has no comparison")

    // An Empty workout has no template to compare with; its sessions never count as one.
    let empty = WorkoutTemplate(
      key: WorkoutRotation.emptyKey, name: "Empty", exercises: push.exercises)
    var free = SetLogger(template: empty, startedAt: start, history: history)
    free.log(at: start + 60)
    let open = try XCTUnwrap(WorkoutSummary(logger: free, endedAt: start + 600, history: history))
    XCTAssertNil(open.lastSessionAt)
    XCTAssertNil(open.exercises[0].change)

    XCTAssertEqual(WorkoutSummary.days(from: summary.lastSessionAt ?? start, to: start), 7)
  }

  func testVolumeExcludesBodyweight() {
    let mixed = past("push", daysAgo: 0, [("Press", 60, 8), ("Dip", nil, 12), ("Press", 62.5, 4)])
    XCTAssertEqual(WorkoutSummary.volume(mixed), 60 * 8 + 62.5 * 4)
    let bodyweight = past("push", daysAgo: 0, [("Dip", nil, 12), ("Dip", nil, 10)])
    XCTAssertNil(WorkoutSummary.volume(bodyweight), "no weighted set is absent, not 0")
  }

  func testUndoFinishRestoresSession() throws {
    var logger = SetLogger(template: push, startedAt: start)
    XCTAssertNil(
      WorkoutSummary(logger: logger, endedAt: start + 60, history: []),
      "a session with no sets has no summary; Finish discards it")
    logger.log(at: start + 60)
    logger.log(at: start + 120)
    let summary = try XCTUnwrap(WorkoutSummary(logger: logger, endedAt: start + 600, history: []))

    // Within 8 s Undo hands back the very logger: same session (same id), the card on the
    // next set, and the last set can still be undone.
    var restored = try XCTUnwrap(summary.undo(at: start + 607))
    XCTAssertEqual(restored, logger)
    XCTAssertEqual(WorkoutFinish.externalID(for: restored.session), summary.done.externalID)
    XCTAssertEqual(restored.exercise?.name, "Dip")
    XCTAssertTrue(restored.canUndo)
    XCTAssertEqual(restored.undo()?.reps, 6)
    XCTAssertEqual(restored.exercise?.name, "Press")

    XCTAssertNil(summary.undo(at: start + 608), "Undo is gone after 8 s")
  }
}
