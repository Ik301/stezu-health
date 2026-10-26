import StezuCore
import XCTest

final class SessionResumeTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)
  private let hour: TimeInterval = 60 * 60

  /// A synthetic template with one three-set exercise, two sets logged 1 and 4 minutes in.
  private func twoSetLogger() -> SetLogger {
    let exercise = TemplateExercise(
      key: "a", name: "Exercise A", sets: 3, repsLow: 8, repsHigh: 12, restSeconds: 90,
      startPounds: 50)
    var logger = SetLogger(
      template: WorkoutTemplate(key: "day-a", name: "Day A", exercises: [exercise]),
      startedAt: start)
    logger.log(at: start + 60)
    logger.log(at: start + 240)
    return logger
  }

  func testUnfinishedSessionIsResumed() {
    let logger = twoSetLogger()
    XCTAssertEqual(SessionResume.atLaunch(nil, now: start), .nothing)

    // Within the idle limit, the logger comes back exactly as saved: same exercise, both sets.
    let soon = SessionResume.atLaunch(logger, now: start + 240 + hour)
    XCTAssertEqual(soon, .resume(logger))
    guard case .resume(let resumed) = soon else { return XCTFail("not resumed") }
    XCTAssertEqual(resumed.exercise?.name, "Exercise A")
    XCTAssertEqual(resumed.loggedSets.count, 2)
    XCTAssertEqual(resumed.setNumber, 3)

    // Exactly at the limit still resumes; only more than the limit closes.
    XCTAssertEqual(SessionResume.atLaunch(logger, now: start + 240 + 3 * hour), .resume(logger))

    // The limit is a default: a longer one keeps a session resumable for longer.
    let config = SessionResumeConfig(idleLimit: 8 * hour)
    XCTAssertEqual(
      SessionResume.atLaunch(logger, now: start + 240 + 5 * hour, config: config),
      .resume(logger))
  }

  func testIdleSessionClosesAtLastSet() {
    let logger = twoSetLogger()
    XCTAssertEqual(SessionResumeConfig().idleLimit, 3 * hour)

    // Idle for more than 3 hours since the last set: closes, ending at that set, not at launch.
    XCTAssertEqual(
      SessionResume.atLaunch(logger, now: start + 240 + 3 * hour + 1),
      .close(logger.session, endedAt: start + 240))
    XCTAssertEqual(
      SessionResume.atLaunch(logger, now: start + 2 * 24 * hour),
      .close(logger.session, endedAt: start + 240))

    // An idle session with no sets has nothing to keep: it is dropped, not closed.
    let empty = SetLogger(
      template: WorkoutTemplate(key: "empty", name: "Empty workout", exercises: []),
      startedAt: start)
    XCTAssertEqual(SessionResume.atLaunch(empty, now: start + 4 * hour), .nothing)
    XCTAssertEqual(SessionResume.atLaunch(empty, now: start + hour), .resume(empty))
  }
}
