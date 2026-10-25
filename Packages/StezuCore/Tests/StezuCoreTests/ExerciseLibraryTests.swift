import Foundation
import XCTest

@testable import StezuCore

final class ExerciseLibraryTests: XCTestCase {
  private let library = ExerciseLibrary(exercises: [
    LibraryExercise(
      key: "bench-press", name: "Bench press", equipment: "Barbell", muscle: "Chest",
      restSeconds: 150),
    LibraryExercise(
      key: "biceps-curl", name: "Biceps curl", equipment: "Dumbbell", muscle: "Arms",
      restSeconds: 60),
    LibraryExercise(
      key: "hammer-curl", name: "Hammer Curl", equipment: "Dumbbell", muscle: "Arms",
      restSeconds: 60),
  ])

  func testSearchIgnoresCase() {
    XCTAssertEqual(library.search("CURL").map(\.key), ["biceps-curl", "hammer-curl"])
    XCTAssertEqual(library.search("bEnCh").map(\.key), ["bench-press"])
    XCTAssertEqual(library.search("  ").count, 3, "an empty query lists everything")
    XCTAssertTrue(library.search("row").isEmpty)
    let groups = library.groupedByMuscle("")
    XCTAssertEqual(groups.map(\.muscle), ["Arms", "Chest"])
    XCTAssertEqual(groups[0].exercises.map(\.key), ["biceps-curl", "hammer-curl"])
  }

  func testCustomExerciseGetsStableKey() throws {
    var mine = library
    let fly = try XCTUnwrap(
      mine.addCustom(name: " Cable Fly! ", equipment: "Cable", muscle: "Chest", restSeconds: 75))
    XCTAssertEqual(fly.key, "custom-cable-fly")
    XCTAssertEqual(fly.name, "Cable Fly!")
    XCTAssertTrue(fly.isCustom)
    XCTAssertFalse(library.exercises[0].isCustom)

    // The same name again gets its own key; the first keeps its key.
    let second = try XCTUnwrap(
      mine.addCustom(name: "cable fly", equipment: "", muscle: "", restSeconds: 60))
    XCTAssertEqual(second.key, "custom-cable-fly-2")
    XCTAssertEqual(second.muscle, "Other")
    XCTAssertEqual(mine.custom.map(\.key), ["custom-cable-fly", "custom-cable-fly-2"])

    // The key survives saving and loading, and the exercise can be found and picked.
    let reloaded = try JSONDecoder().decode(ExerciseLibrary.self, from: JSONEncoder().encode(mine))
    // Sorted by name: "cable fly" comes before "Cable Fly!".
    XCTAssertEqual(reloaded.search("fly").map(\.key), ["custom-cable-fly-2", "custom-cable-fly"])

    XCTAssertNil(mine.addCustom(name: "  ", equipment: "", muscle: "", restSeconds: 60))
    XCTAssertNil(mine.addCustom(name: "Row", equipment: "", muscle: "", restSeconds: 0))
  }

  func testSwapChangesThisSessionOnlyAndLastDone() throws {
    let bench = TemplateExercise(
      key: "bench-press", name: "Bench press", sets: 3, repsLow: 6, repsHigh: 10,
      restSeconds: 150, startPounds: 45)
    let template = WorkoutTemplate(key: "day-1", name: "Day 1", exercises: [bench])
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var past = WorkoutSession(startedAt: now.addingTimeInterval(-7 * 86_400))
    past.logSet("Hammer Curl", pounds: 30, reps: 12, at: past.startedAt)

    var logger = SetLogger(template: template, startedAt: now)
    logger.swap(to: library.exercises[2], history: [past])
    XCTAssertEqual(logger.exercise?.name, "Hammer Curl")
    XCTAssertEqual(logger.exercise?.sets, 3)
    XCTAssertEqual(logger.exercise?.restSeconds, 60)
    XCTAssertEqual(logger.pounds, 30, "prefilled from its last session")
    XCTAssertEqual(logger.template, template, "the template is unchanged")

    logger.log(at: now)
    XCTAssertEqual(logger.session.sets(for: "Hammer Curl")?.count, 1)
    XCTAssertNotNil(logger.undo())
    XCTAssertNil(logger.session.sets(for: "Hammer Curl"))

    XCTAssertEqual(ExerciseLibrary.lastDone("Hammer Curl", before: now, in: [past]), "7d ago")
    XCTAssertEqual(ExerciseLibrary.lastDone("Bench press", before: now, in: [past]), "--")
  }
}
