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

  /// A generic add-on block: two exercises, the second never logged in the tests.
  private let core = WorkoutTemplate(
    key: "core", name: "Core",
    exercises: [
      TemplateExercise(
        key: "crunch", name: "Crunch", sets: 2, repsLow: 10, repsHigh: 15, restSeconds: 45,
        startPounds: 10),
      TemplateExercise(
        key: "plank", name: "Plank", sets: 1, repsLow: 1, repsHigh: 1, restSeconds: 30),
    ], addOn: true)

  func testAppendAddOnKeepsOneSessionAndSkipsUnloggedExercises() throws {
    var logger = SetLogger(template: template(sets: 1), startedAt: start)
    logger.append(core, history: [])
    XCTAssertEqual(logger.exercise?.key, "a", "the card stays on the day's unfinished exercise")
    XCTAssertEqual(logger.exercises.map(\.key), ["a", "b", "crunch", "plank"])
    logger.append(core, history: [])
    XCTAssertEqual(logger.exercises.count, 4, "an add-on is appended once")

    logger.log(at: start.addingTimeInterval(60))
    logger.log(at: start.addingTimeInterval(120))
    XCTAssertEqual(logger.exercise?.key, "crunch", "the card moves on into the add-on")
    XCTAssertEqual(logger.exercise?.restSeconds, 45)
    XCTAssertEqual(logger.pounds, 10, "the add-on exercise starts at its own numbers")
    let crunch = try XCTUnwrap(logger.log(at: start.addingTimeInterval(180)))
    XCTAssertEqual(logger.setNumber, 2)
    XCTAssertEqual(logger.undo(), crunch, "undo takes back the add-on set")
    XCTAssertNotNil(logger.log(at: start.addingTimeInterval(200)))

    // Saved mid-workout and loaded again, the appended exercises and their sets are kept.
    let saved = try JSONDecoder().decode(SetLogger.self, from: JSONEncoder().encode(logger))
    XCTAssertEqual(saved, logger)
    XCTAssertEqual(saved.addOns.map(\.key), ["core"])

    // One session under the day's key; Plank, never logged, is left out.
    let session = saved.session
    XCTAssertEqual(session.templateKey, "t")
    XCTAssertEqual(session.exercises.map(\.exercise), ["Lift A", "Lift B", "Crunch"])
    let done = try XCTUnwrap(WorkoutFinish.close(session, at: start.addingTimeInterval(300)))
    let keys = Dictionary(uniqueKeysWithValues: saved.exercises.map { ($0.name, $0.key) })
    let record = SyncRecord.session(done, templateName: "T", keys: keys, at: start)
    let payload = try XCTUnwrap(record.sessionPayload)
    XCTAssertEqual(payload.templateKey, "t")
    XCTAssertEqual(payload.exercises.map(\.key), ["a", "b", "crunch"])
    XCTAssertEqual(payload.exercises.last?.sets.map(\.exerciseKey), ["crunch"])

    // Appended after the day's exercises are done, the card goes straight to the add-on.
    var later = SetLogger(template: template(sets: 1), startedAt: start)
    later.log(at: start.addingTimeInterval(60))
    later.log(at: start.addingTimeInterval(120))
    later.append(core, history: [])
    XCTAssertEqual(later.exercise?.key, "crunch")
    XCTAssertEqual(later.pounds, 10)

    // A logger saved before add-ons existed has none.
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(logger)) as? [String: Any])
    json["appended"] = nil
    let old = try JSONDecoder().decode(
      SetLogger.self, from: JSONSerialization.data(withJSONObject: json))
    XCTAssertTrue(old.addOns.isEmpty)
    XCTAssertEqual(old.exercises.map(\.key), ["a", "b"])
  }

  func testAddOnLastNumbersComeFromAnyTemplate() throws {
    let day: TimeInterval = 86_400
    func past(_ key: String, daysAgo: Double, _ sets: [(String, Double)]) -> WorkoutSession {
      var session = WorkoutSession(startedAt: start - daysAgo * day, templateKey: key)
      for (name, pounds) in sets {
        session.logSet(name, pounds: pounds, reps: 12, at: session.startedAt + 60)
      }
      return session
    }
    let history = [
      past("t", daysAgo: 6, [("Lift A", 100), ("Crunch", 15)]),
      past("other", daysAgo: 2, [("Lift A", 80), ("Crunch", 25)]),
    ]
    var logger = SetLogger(template: template(sets: 1), startedAt: start, history: history)
    XCTAssertEqual(logger.lastNumbers?.sets.first?.pounds, 100, "a day exercise keeps D-046")
    logger.append(core, history: history)
    let crunch = try XCTUnwrap(logger.last["Crunch"])
    XCTAssertEqual(crunch.sets.first?.pounds, 25, "the add-on uses the latest session of any day")
    XCTAssertEqual(crunch.daysAgo, 2)
    XCTAssertNil(logger.last["Plank"], "never done: absent, not zero")

    logger.log(at: start + 60)
    logger.log(at: start + 120)
    XCTAssertEqual(logger.exercise?.key, "crunch")
    XCTAssertEqual(logger.pounds, 25, "prefilled from that session")
  }
}
