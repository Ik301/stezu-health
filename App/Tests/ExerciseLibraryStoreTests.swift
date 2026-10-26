import StezuCore
import XCTest

@testable import StezuHealth

final class ExerciseLibraryStoreTests: XCTestCase {
  func testBundledLibraryHasEveryTemplateExercise() throws {
    let library = ExerciseLibraryStore(storage: .memory).load()
    let seed = try XCTUnwrap(WorkoutTemplateStore.bundledSeed(), "PrebuiltWorkouts.json missing")
    let names = Set(library.exercises.map(\.name))
    for exercise in seed.templates.flatMap(\.exercises) {
      XCTAssertTrue(names.contains(exercise.name), "\(exercise.name) is not in the library")
    }
    XCTAssertTrue(library.custom.isEmpty)
  }

  func testCustomExercisesSurviveRelaunch() throws {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ExerciseLibraryStore(storage: .temporary(folder))
    var library = store.load()
    let count = library.exercises.count
    library.addCustom(name: "Cable fly", equipment: "Cable", muscle: "Chest", restSeconds: 75)
    store.save(library)

    let reloaded = store.load()
    XCTAssertEqual(reloaded.exercises.count, count + 1)
    XCTAssertEqual(reloaded.custom.map(\.key), ["custom-cable-fly"])
  }
}
