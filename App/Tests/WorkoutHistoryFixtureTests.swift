import StezuCore
import XCTest

@testable import StezuHealth

final class WorkoutHistoryFixtureTests: XCTestCase {
  func testWorkoutHistoryScenarioSeedsSyntheticSessions() {
    let environment = AppEnvironment.fromLaunch(
      arguments: ["-uitest", "-uitest-scenario", "workout-history"])
    let history = environment.workoutHistory
    XCTAssertEqual(history.map(\.templateKey), ["day-1", "day-2"])
    XCTAssertTrue(AppEnvironment.fromLaunch(arguments: ["-uitest"]).workoutHistory.isEmpty)

    let bench = TemplateHistory.lastSession(
      of: "Bench press", template: "day-1", before: Date(), in: history)
    XCTAssertEqual(bench?.summary(setAt: 0), "Last 60 x 8, 7d ago")
  }
}
