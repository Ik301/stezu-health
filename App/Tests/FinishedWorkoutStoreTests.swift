import StezuCore
import XCTest

@testable import StezuHealth

final class FinishedWorkoutStoreTests: XCTestCase {
  func testFinishedWorkoutsAreSavedAndReloaded() {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = FinishedWorkoutStore(storage: .temporary(folder))
    XCTAssertTrue(store.load().isEmpty, "no finished workouts yet")

    var session = WorkoutSession(startedAt: Date(timeIntervalSince1970: 1_800_000_000))
    session.logSet("A", pounds: nil, reps: 10, at: session.startedAt + 60)
    let workout = FinishedWorkout(
      session: session, endedAt: session.startedAt + 600,
      externalID: WorkoutFinish.externalID(for: session), inHealth: false)
    store.save([workout])

    XCTAssertEqual(store.load(), [workout])
    XCTAssertTrue(FinishedWorkoutStore(storage: .memory).load().isEmpty)
  }
}
