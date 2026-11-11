import Foundation
import XCTest

@testable import StezuCore

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

  /// S-046: Skip exercise moves the card to the next exercise, prefilled, without logging; an
  /// exercise skipped with no sets is not in the session, one skipped part-way keeps its sets.
  func testSkipExerciseMovesOnWithoutLogging() throws {
    var logger = SetLogger(template: template(), startedAt: start)
    XCTAssertEqual(logger.upNext?.key, "b")
    logger.skipExercise()
    XCTAssertEqual(logger.exercise?.key, "b")
    XCTAssertEqual(logger.exerciseIndex, 1)
    XCTAssertEqual(logger.setNumber, 1)
    XCTAssertEqual(logger.pounds, 20, "prefilled with the next exercise's start")
    XCTAssertEqual(logger.reps, 8)
    XCTAssertNil(logger.upNext, "the last exercise has nothing up next")
    XCTAssertTrue(logger.session.exercises.isEmpty, "skipping logs nothing")
    XCTAssertFalse(logger.canUndo, "a skip is not a set to undo")

    logger.skipExercise()
    XCTAssertEqual(logger.exercise?.key, "b", "the last exercise cannot be skipped")
    XCTAssertNotNil(logger.log(at: start + 60))
    XCTAssertEqual(logger.session.exercises.map(\.exercise), ["Lift B"], "Lift A is left out")

    var partWay = SetLogger(template: template(sets: 3), startedAt: start)
    partWay.log(at: start + 60)
    partWay.skipExercise()
    XCTAssertEqual(partWay.exercise?.key, "b")
    XCTAssertEqual(partWay.session.sets(for: "Lift A")?.count, 1, "the logged set stays")
    XCTAssertNotNil(partWay.undo())
    XCTAssertEqual(partWay.exercise?.key, "a", "undo returns to the skipped exercise's set")
  }

  /// Generic library exercises (D-034).
  private let fly = LibraryExercise(
    key: "dumbbell-fly", name: "Dumbbell fly", equipment: "Dumbbell", muscle: "Chest",
    restSeconds: 75)
  private let curl = LibraryExercise(
    key: "biceps-curl", name: "Biceps curl", equipment: "Dumbbell", muscle: "Arms",
    restSeconds: 60)

  /// An Empty workout starts with no slot; Add exercise gives it one that can be logged.
  func testAddExerciseToEmptyWorkout() throws {
    let empty = WorkoutTemplate(key: WorkoutRotation.emptyKey, name: "Empty", exercises: [])
    var logger = SetLogger(template: empty, startedAt: start)
    XCTAssertNil(logger.exercise)
    XCTAssertFalse(logger.canLog)

    logger.add(fly, history: [])
    let slot = try XCTUnwrap(logger.exercise, "the card moves to the added exercise")
    XCTAssertEqual(slot.key, "dumbbell-fly")
    XCTAssertEqual(slot.name, "Dumbbell fly")
    XCTAssertEqual(slot.sets, SetLogger.addedSets)
    XCTAssertEqual(slot.repRange, "8-12")
    XCTAssertEqual(slot.restSeconds, 75, "the rest comes from the library exercise")
    XCTAssertNil(logger.pounds, "never done: no weight, \"--\"")
    XCTAssertEqual(logger.reps, 8)
    XCTAssertNil(logger.lastNumbers)

    logger.stepWeight(up: true)
    XCTAssertTrue(logger.canLog)
    let set = try XCTUnwrap(logger.log(at: start + 60))
    XCTAssertEqual(set.pounds, SetLogger.defaultWeightStep)
    XCTAssertEqual(logger.loggedSets.count, 1)
    XCTAssertEqual(logger.undo(), set, "an added exercise's set can be undone")
    logger.log(at: start + 90)

    // Logs like any other: one session under the Empty key with the library key on its sets.
    let done = try XCTUnwrap(WorkoutFinish.close(logger.session, at: start + 300))
    XCTAssertEqual(done.session.templateKey, WorkoutRotation.emptyKey)
    let keys = Dictionary(uniqueKeysWithValues: logger.exercises.map { ($0.name, $0.key) })
    let record = SyncRecord.session(done, templateName: "Empty", keys: keys, at: start)
    let payload = try XCTUnwrap(record.sessionPayload)
    XCTAssertEqual(payload.exercises.map(\.key), ["dumbbell-fly"])
    XCTAssertEqual(payload.exercises.first?.sets.count, 1)
  }

  /// In a normal workout the added slot goes last; the card only jumps to it once the card's
  /// exercise has all its sets. Its last numbers come from any template, as Swap's do.
  func testAddExerciseToRunningWorkout() throws {
    var past = WorkoutSession(startedAt: start - 3 * 86_400, templateKey: "other")
    past.logSet("Biceps curl", pounds: 25, reps: 11, at: past.startedAt + 60)
    var logger = SetLogger(template: template(sets: 1), startedAt: start, history: [past])

    logger.add(curl, history: [past])
    XCTAssertEqual(logger.exercises.map(\.key), ["a", "b", "biceps-curl"])
    XCTAssertEqual(logger.exercise?.key, "a", "the card stays on the unfinished exercise")
    XCTAssertEqual(logger.last["Biceps curl"]?.sets.first?.pounds, 25)

    logger.log(at: start + 60)
    logger.log(at: start + 120)
    XCTAssertEqual(logger.exercise?.key, "biceps-curl", "the card moves on into the added slot")
    XCTAssertEqual(logger.pounds, 25, "prefilled from its last session")
    XCTAssertEqual(logger.reps, 11)

    // Added after every set is done, the card goes straight to the new slot.
    for minute in 3...5 { logger.log(at: start + Double(minute) * 60) }
    XCTAssertEqual(logger.loggedSets.count, SetLogger.addedSets)
    logger.add(fly, history: [past])
    XCTAssertEqual(logger.exercise?.key, "dumbbell-fly")
    XCTAssertEqual(logger.exercises.count, 4)

    // The same exercise can be added twice; each add is its own slot.
    logger.add(fly, history: [past])
    XCTAssertEqual(logger.exercises.map(\.key).filter { $0 == "dumbbell-fly" }.count, 2)
  }

  /// The added slots and their sets survive the session store's save and load (JSON).
  func testAddedExerciseSurvivesSaveAndRestore() throws {
    let empty = WorkoutTemplate(key: WorkoutRotation.emptyKey, name: "Empty", exercises: [])
    var logger = SetLogger(template: empty, startedAt: start)
    logger.add(fly, history: [])
    logger.toggleBodyweight()
    logger.log(at: start + 60)

    let saved = try JSONDecoder().decode(SetLogger.self, from: JSONEncoder().encode(logger))
    XCTAssertEqual(saved, logger)
    XCTAssertEqual(saved.exercise?.key, "dumbbell-fly")
    XCTAssertEqual(saved.setNumber, 2)
    XCTAssertEqual(saved.session.sets(for: "Dumbbell fly")?.count, 1)

    var resumed = saved
    resumed.add(curl, history: [])
    XCTAssertEqual(resumed.exercises.map(\.key), ["dumbbell-fly", "biceps-curl"])
    XCTAssertNotNil(resumed.undo(), "undo still reaches the set logged before the save")
  }

  /// Sets and reps stay in range: 1 to 10 sets, reps from 1, the high end never below the low
  /// end; stepping one end past the other carries it along, and equal ends read as one number.
  func testSlotShapeStepsStayInRange() {
    var shape = SlotShape.added
    XCTAssertEqual(shape.summary, "3 x 8-12")
    for _ in 0..<12 { shape.stepSets(up: true) }
    XCTAssertEqual(shape.sets, SlotShape.maxSets)
    for _ in 0..<12 { shape.stepSets(up: false) }
    XCTAssertEqual(shape.sets, 1)

    for _ in 0..<6 { shape.stepRepsLow(up: true) }
    XCTAssertEqual(shape.repRange, "14", "the low end pushes the high end along")
    for _ in 0..<4 { shape.stepRepsHigh(up: false) }
    XCTAssertEqual(shape.repRange, "10", "the high end pulls the low end along")
    shape.stepRepsHigh(up: true)
    shape.stepRepsHigh(up: true)
    XCTAssertEqual(shape.summary, "1 x 10-12")
    for _ in 0..<20 { shape.stepRepsLow(up: false) }
    XCTAssertEqual(shape.repsLow, 1)

    XCTAssertEqual(SlotShape(sets: 0, repsLow: 12, repsHigh: 8).summary, "1 x 12")
    XCTAssertEqual(SlotShape(sets: 40, repsLow: 0, repsHigh: 500).summary, "10 x 1-100")
  }

  /// Add exercise with chosen sets and reps: the slot has them, the card starts at the low end
  /// and moves on after the chosen number of sets.
  func testAddExerciseWithChosenSetsAndReps() throws {
    let empty = WorkoutTemplate(key: WorkoutRotation.emptyKey, name: "Empty", exercises: [])
    var logger = SetLogger(template: empty, startedAt: start)
    logger.add(fly, shape: SlotShape(sets: 2, repsLow: 15, repsHigh: 15), history: [])
    logger.add(curl, history: [])
    let slot = try XCTUnwrap(logger.exercise)
    XCTAssertEqual(slot.sets, 2)
    XCTAssertEqual(slot.repRange, "15")
    XCTAssertEqual(slot.restSeconds, 75)
    XCTAssertEqual(logger.reps, 15)
    XCTAssertEqual(logger.exercises.last?.repRange, "8-12", "no shape chosen: 3 x 8-12")

    logger.toggleBodyweight()
    logger.log(at: start + 60)
    logger.log(at: start + 120)
    XCTAssertEqual(logger.exercise?.key, "biceps-curl", "two sets chosen, two sets done")
  }

  /// Sets and reps on an added slot already in the session: it changes that slot only, keeps
  /// at least the sets already logged, survives a save, and moves the card on once the slot
  /// has all its sets. Program slots cannot be changed.
  func testReshapeAddedSlotInSession() throws {
    var logger = SetLogger(template: template(sets: 1), startedAt: start)
    XCTAssertFalse(logger.canReshape, "a program slot keeps its sets and reps")
    logger.reshape(SlotShape(sets: 5, repsLow: 1, repsHigh: 1))
    XCTAssertEqual(logger.exercise?.sets, 1)

    logger.log(at: start + 60)
    logger.log(at: start + 120)
    logger.add(fly, history: [])
    logger.add(curl, history: [])
    XCTAssertEqual(logger.exercise?.key, "dumbbell-fly")
    XCTAssertTrue(logger.canReshape)
    logger.reshape(SlotShape(sets: 4, repsLow: 10, repsHigh: 10))
    XCTAssertEqual(logger.exercise?.sets, 4)
    XCTAssertEqual(logger.exercise?.repRange, "10")
    XCTAssertEqual(logger.reps, 10, "nothing logged and never done: the card starts at 10")
    XCTAssertEqual(logger.exercises.last?.sets, SetLogger.addedSets, "the other added slot")

    logger.toggleBodyweight()
    logger.log(at: start + 180)
    logger.log(at: start + 240)
    logger.stepReps(up: true)
    logger.reshape(SlotShape(sets: 1, repsLow: 6, repsHigh: 8))
    XCTAssertEqual(
      logger.exercises[2].sets, 2, "never fewer sets than logged; the slot is now done")
    XCTAssertEqual(logger.exercise?.key, "biceps-curl", "the card moves on as after a Log")

    let saved = try JSONDecoder().decode(SetLogger.self, from: JSONEncoder().encode(logger))
    XCTAssertEqual(saved.exercises[2].sets, 2)
    XCTAssertEqual(saved.exercises[2].repRange, "6-8")
  }
}
