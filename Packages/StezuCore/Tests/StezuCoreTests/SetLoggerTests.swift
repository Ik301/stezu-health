import Foundation
import StezuCore
import XCTest

// Generic exercises and numbers, not anyone's program (D-034).
final class SetLoggerTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_700_000_000)

  private func template(sets: Int = 2, startPounds: Double? = 45) -> WorkoutTemplate {
    WorkoutTemplate(
      key: "t", name: "T",
      exercises: [
        TemplateExercise(
          key: "a", name: "Lift A", sets: sets, repsLow: 6, repsHigh: 10, restSeconds: 90,
          startPounds: startPounds),
        TemplateExercise(
          key: "b", name: "Lift B", sets: sets, repsLow: 8, repsHigh: 12, restSeconds: 60,
          weightStep: 2.5, startPounds: 20),
      ])
  }

  func testUndoRemovesOnlyLastSet() throws {
    var logger = SetLogger(template: template(), startedAt: start)
    XCTAssertEqual(logger.pounds, 45)
    XCTAssertEqual(logger.reps, 6)
    XCTAssertEqual(logger.setNumber, 1)

    XCTAssertNotNil(logger.log(at: start.addingTimeInterval(60)))
    XCTAssertEqual(logger.setNumber, 2)
    XCTAssertEqual(logger.pounds, 45, "the next set keeps the same numbers")
    logger.stepWeight(up: true)
    logger.stepReps(up: false)
    XCTAssertNotNil(logger.log(at: start.addingTimeInterval(120)))
    // Two sets of two: the card moves to the next exercise with its own starting numbers.
    XCTAssertEqual(logger.exercise?.key, "b")
    XCTAssertEqual(logger.pounds, 20)

    let undone = try XCTUnwrap(logger.undo())
    XCTAssertEqual(undone.pounds, 50)
    XCTAssertEqual(undone.reps, 5)
    XCTAssertEqual(logger.exercise?.key, "a", "the card returns to the undone set")
    XCTAssertEqual(logger.setNumber, 2)
    XCTAssertEqual(logger.pounds, 50)
    XCTAssertEqual(logger.reps, 5)
    XCTAssertEqual(logger.session.sets(for: "Lift A")?.map(\.pounds), [45], "first set kept")

    XCTAssertNotNil(logger.undo())
    XCTAssertNil(logger.session.sets(for: "Lift A"))
    XCTAssertNil(logger.undo(), "nothing left to undo")
  }

  func testSteppersStayInRange() {
    var logger = SetLogger(template: template(), startedAt: start)
    for _ in 0..<20 { logger.stepWeight(up: false) }
    XCTAssertEqual(logger.pounds, 5, "weight stops at one step, never 0")
    for _ in 0..<20 { logger.stepReps(up: false) }
    XCTAssertEqual(logger.reps, 1)
    for _ in 0..<500 { logger.stepWeight(up: true) }
    XCTAssertEqual(logger.pounds, SetLogger.maxPounds)
    for _ in 0..<200 { logger.stepReps(up: true) }
    XCTAssertEqual(logger.reps, SetLogger.maxReps)

    // No starting weight: "--" until a step sets one; Log is off until then.
    var empty = SetLogger(template: template(startPounds: nil), startedAt: start)
    XCTAssertNil(empty.pounds)
    XCTAssertFalse(empty.canLog)
    XCTAssertNil(empty.log(at: start))
    empty.stepWeight(up: false)
    XCTAssertNil(empty.pounds)
    empty.stepWeight(up: true)
    XCTAssertEqual(empty.pounds, SetLogger.defaultWeightStep)
    XCTAssertTrue(empty.canLog)
  }

  func testBodyweightIsNilNotZero() throws {
    var logger = SetLogger(template: template(startPounds: nil), startedAt: start)
    logger.toggleBodyweight()
    XCTAssertTrue(logger.canLog)
    logger.stepWeight(up: true)
    XCTAssertNil(logger.pounds, "weight steppers do nothing on a bodyweight set")
    let set = try XCTUnwrap(logger.log(at: start))
    XCTAssertNil(set.pounds)
    XCTAssertNil(logger.session.sets(for: "Lift A")?.first?.pounds)

    let data = try JSONEncoder().encode(logger)
    let saved = try JSONDecoder().decode(SetLogger.self, from: data)
    XCTAssertEqual(saved, logger)
    XCTAssertNil(saved.session.sets(for: "Lift A")?.first?.pounds, "stored as nil, never 0")

    logger.undo()
    XCTAssertTrue(logger.isBodyweight, "undo returns the card to the bodyweight set")
  }
}
