import StezuCore
import XCTest

@testable import StezuHealth

final class WorkoutSessionStoreTests: XCTestCase {
  func testLoggedSetIsSavedAndReloaded() throws {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WorkoutSessionStore(storage: .temporary(folder))
    XCTAssertNil(store.load(), "no workout in progress yet")

    let exercise = TemplateExercise(
      key: "a", name: "A", sets: 3, repsLow: 8, repsHigh: 12, restSeconds: 60)
    var logger = SetLogger(
      template: WorkoutTemplate(key: "t", name: "T", exercises: [exercise]), startedAt: Date())
    logger.toggleBodyweight()
    logger.log(at: Date())
    store.save(logger)

    let saved = try XCTUnwrap(store.load())
    XCTAssertEqual(saved, logger)
    XCTAssertEqual(saved.session.sets(for: "A")?.count, 1)
    XCTAssertNil(saved.session.sets(for: "A")?.first?.pounds, "bodyweight is nil, not 0")
    XCTAssertNil(WorkoutSessionStore(storage: .memory).load())
  }
}
