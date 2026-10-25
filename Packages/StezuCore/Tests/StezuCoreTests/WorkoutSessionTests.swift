import Foundation
import StezuCore
import XCTest

// All weights and reps are made-up example numbers, not anyone's data.
final class WorkoutSessionTests: XCTestCase {
  private var config: WorkoutHistoryConfig {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return WorkoutHistoryConfig(calendar: calendar)
  }

  private let start = Date(timeIntervalSince1970: 1_700_000_000)

  private func day(_ offset: Int, minute: Int = 0) -> Date {
    start.addingTimeInterval(Double(offset) * 86_400 + Double(minute) * 60)
  }

  func testLogSetIsOneCall() {
    var session = WorkoutSession(startedAt: day(0))

    let first = session.logSet("Squat", pounds: 100, reps: 8, at: day(0, minute: 1))
    session.logSet("Squat", pounds: 100, reps: 7, at: day(0, minute: 4))
    session.logSet("Pull-up", pounds: nil, reps: 5, at: day(0, minute: 10))

    XCTAssertEqual(first, WorkoutSet(pounds: 100, reps: 8, loggedAt: day(0, minute: 1)))
    XCTAssertEqual(session.exercises.map(\.exercise), ["Squat", "Pull-up"])
    XCTAssertEqual(session.sets(for: "Squat")?.map(\.reps), [8, 7])
    XCTAssertEqual(session.sets(for: "Pull-up")?.first?.pounds, nil)
    XCTAssertNil(session.sets(for: "Bench"))

    // Not-a-set inputs change nothing.
    XCTAssertNil(session.logSet("Squat", pounds: 100, reps: 0, at: day(0, minute: 12)))
    XCTAssertNil(session.logSet("Squat", pounds: 0, reps: 5, at: day(0, minute: 12)))
    XCTAssertNil(session.logSet("Squat", pounds: -5, reps: 5, at: day(0, minute: 12)))
    XCTAssertNil(session.logSet("Squat", pounds: .nan, reps: 5, at: day(0, minute: 12)))
    XCTAssertNil(session.logSet("Bench", pounds: 50, reps: -1, at: day(0, minute: 12)))
    XCTAssertEqual(session.sets(for: "Squat")?.count, 2)
    XCTAssertNil(session.sets(for: "Bench"))
  }

  func testLastSessionNumbersPerExercise() {
    var older = WorkoutSession(startedAt: day(0))
    older.logSet("Squat", pounds: 100, reps: 8, at: day(0, minute: 1))
    older.logSet("Bench", pounds: 60, reps: 10, at: day(0, minute: 10))

    var newer = WorkoutSession(startedAt: day(3))
    newer.logSet("Squat", pounds: 105, reps: 6, at: day(3, minute: 1))
    newer.logSet("Squat", pounds: 105, reps: 5, at: day(3, minute: 4))

    var today = WorkoutSession(startedAt: day(7))
    today.logSet("Squat", pounds: 110, reps: 5, at: day(7, minute: 1))

    let empty = WorkoutSession(startedAt: day(5))
    let sessions = [newer, today, empty, older]

    // Squat: the latest earlier session, not today's and not the older one.
    let squat = WorkoutHistory.lastSession(
      of: "Squat", before: day(7), in: sessions, config: config)
    XCTAssertEqual(squat?.sessionStartedAt, day(3))
    XCTAssertEqual(squat?.sets.map(\.reps), [6, 5])
    XCTAssertEqual(squat?.sets.map(\.pounds), [105, 105])
    XCTAssertEqual(squat?.daysAgo, 4)
    XCTAssertEqual(squat?.confidence.level, .high)

    // Bench: skipped in the newer session, so it falls back to the one that had it.
    let bench = WorkoutHistory.lastSession(
      of: "Bench", before: day(7), in: sessions, config: config)
    XCTAssertEqual(bench?.sessionStartedAt, day(0))
    XCTAssertEqual(bench?.sets.map(\.reps), [10])
    XCTAssertEqual(bench?.daysAgo, 7)

    // Never done before, or no earlier session at all: absent, not zero.
    XCTAssertNil(
      WorkoutHistory.lastSession(of: "Deadlift", before: day(7), in: sessions, config: config))
    XCTAssertNil(
      WorkoutHistory.lastSession(of: "Squat", before: day(0), in: sessions, config: config))
    XCTAssertNil(WorkoutHistory.lastSession(of: "Squat", before: day(7), in: [], config: config))

    let all = WorkoutHistory.lastSessions(before: day(7), in: sessions, config: config)
    XCTAssertEqual(Set(all.keys), ["Squat", "Bench"])
    XCTAssertEqual(all["Squat"], squat)

    // Confidence fades as the last session ages.
    let stale = WorkoutHistory.lastSession(
      of: "Bench", before: day(30), in: [older], config: config)
    XCTAssertEqual(stale?.confidence.level, .medium)
    let old = WorkoutHistory.lastSession(of: "Bench", before: day(60), in: [older], config: config)
    XCTAssertEqual(old?.confidence.level, .low)
    XCTAssertEqual(old?.confidence.reason, "1 set, 60 days ago")
  }
}
