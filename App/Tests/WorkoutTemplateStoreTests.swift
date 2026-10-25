import StezuCore
import XCTest

@testable import StezuHealth

final class WorkoutTemplateStoreTests: XCTestCase {
  func testBundledSeedShipsInTheApp() throws {
    let seed = try XCTUnwrap(WorkoutTemplateStore.bundledSeed(), "PrebuiltWorkouts.json missing")
    XCTAssertEqual(seed.templates.count, 5)
    let library = WorkoutTemplateStore(storage: .memory).load(seed: seed)
    XCTAssertEqual(library.next(after: nil)?.key, "day-1")
  }

  func testSeedIsAppliedOnceAndEditsSurviveRelaunch() throws {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WorkoutTemplateStore(storage: .temporary(folder))
    let exercise = TemplateExercise(
      key: "a", name: "A", sets: 3, repsLow: 8, repsHigh: 12, restSeconds: 60)
    let seed = WorkoutSeed(
      seedVersion: 1, templates: [WorkoutTemplate(key: "t", name: "T", exercises: [exercise])])

    var library = store.load(seed: seed)
    library.edit(WorkoutTemplate(key: "t", name: "Mine", exercises: [exercise]))
    store.save(library)

    let newer = WorkoutSeed(
      seedVersion: 2, templates: [WorkoutTemplate(key: "t", name: "T2", exercises: [exercise])])
    let reloaded = store.load(seed: newer)
    XCTAssertEqual(reloaded.seedVersion, 2)
    XCTAssertEqual(reloaded.templates.map(\.name), ["Mine"])
  }
}
