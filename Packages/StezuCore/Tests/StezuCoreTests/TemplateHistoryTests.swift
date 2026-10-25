import Foundation
import StezuCore
import XCTest

// All weights and reps are made-up example numbers, not anyone's data.
final class TemplateHistoryTests: XCTestCase {
  private var config: WorkoutHistoryConfig {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return WorkoutHistoryConfig(calendar: calendar)
  }

  private let start = Date(timeIntervalSince1970: 1_700_000_000)

  private func day(_ offset: Int, minute: Int = 0) -> Date {
    start.addingTimeInterval(Double(offset) * 86_400 + Double(minute) * 60)
  }

  private func session(
    _ template: String?, day offset: Int, _ sets: [(String, Double?, Int)]
  ) -> WorkoutSession {
    var session = WorkoutSession(startedAt: day(offset), templateKey: template)
    for (index, set) in sets.enumerated() {
      session.logSet(set.0, pounds: set.1, reps: set.2, at: day(offset, minute: index + 1))
    }
    return session
  }

  private let dayOne = WorkoutTemplate(
    key: "day-1", name: "Day 1",
    exercises: [
      TemplateExercise(
        key: "bench", name: "Bench", sets: 2, repsLow: 6, repsHigh: 10, restSeconds: 90,
        startPounds: 45),
      TemplateExercise(
        key: "press", name: "Press", sets: 1, repsLow: 8, repsHigh: 12, restSeconds: 90),
      TemplateExercise(
        key: "fly", name: "Fly", sets: 1, repsLow: 10, repsHigh: 15, restSeconds: 60),
    ])

  func testPrefersSameTemplate() {
    let history = [
      session("day-1", day: 0, [("Bench", 60, 8), ("Bench", 60, 7)]),
      session("day-2", day: 5, [("Bench", 65, 5)]),
    ]

    let bench = TemplateHistory.lastSession(
      of: "Bench", template: "day-1", before: day(7), in: history, config: config)
    XCTAssertEqual(bench?.sessionStartedAt, day(0), "the newer Day 2 session was used")
    XCTAssertEqual(bench?.daysAgo, 7)
    XCTAssertEqual(bench?.summary(setAt: 0), "Last 60 x 8, 7d ago")
    XCTAssertEqual(bench?.summary(setAt: 1), "Last 60 x 7, 7d ago")
    XCTAssertEqual(bench?.summary(setAt: 2), "Last 60 x 7, 7d ago", "past its sets: its last")
    XCTAssertEqual(bench?.confidence.level, .high)

    // The logger prefills from it and stores the new session under the template.
    let logger = SetLogger(template: dayOne, startedAt: day(7), history: history, config: config)
    XCTAssertEqual(logger.pounds, 60)
    XCTAssertEqual(logger.reps, 8)
    XCTAssertTrue(logger.canLog)
    XCTAssertEqual(logger.lastNumbers?.sessionStartedAt, day(0))
    XCTAssertEqual(logger.session.templateKey, "day-1")
  }

  func testFallsBackToAnyTemplate() {
    let history = [
      session("day-1", day: 0, [("Bench", 60, 8)]),
      session("day-2", day: 3, [("Press", nil, 10)]),
      session(nil, day: 5, [("Press", 30, 9)]),
    ]

    let press = TemplateHistory.lastSession(
      of: "Press", template: "day-1", before: day(7), in: history, config: config)
    XCTAssertEqual(press?.sessionStartedAt, day(5), "no Day 1 session had it: the latest of any")
    XCTAssertEqual(press?.summary(setAt: 0), "Last 30 x 9, 2d ago")

    // Without a template key every session counts.
    let any = TemplateHistory.lastSession(
      of: "Bench", template: nil, before: day(7), in: history, config: config)
    XCTAssertEqual(any?.sessionStartedAt, day(0))

    // After Bench's two sets the card moves to Press, prefilled from the fallback.
    var logger = SetLogger(template: dayOne, startedAt: day(7), history: history, config: config)
    logger.log(at: day(7, minute: 1))
    logger.log(at: day(7, minute: 3))
    XCTAssertEqual(logger.exercise?.name, "Press")
    XCTAssertEqual(logger.pounds, 30)
    XCTAssertEqual(logger.reps, 9)
    XCTAssertFalse(logger.isBodyweight)

    // A bodyweight last set prefills bodyweight, not 0.
    let bodyweight = [session("day-1", day: 6, [("Press", nil, 12)])]
    var other = SetLogger(template: dayOne, startedAt: day(7), history: bodyweight, config: config)
    other.log(at: day(7, minute: 1))
    other.log(at: day(7, minute: 2))
    XCTAssertTrue(other.isBodyweight)
    XCTAssertNil(other.pounds)
    XCTAssertEqual(other.lastNumbers?.summary(setAt: 0), "Last BW x 12, 1d ago")
  }

  func testFirstEverExerciseIsAbsent() {
    let history = [
      session("day-1", day: 0, [("Bench", 60, 8)]),
      session("day-1", day: 9, [("Fly", 20, 12)]),
    ]

    // Never done, or only done later: nil, never zero.
    XCTAssertNil(
      TemplateHistory.lastSession(
        of: "Fly", template: "day-1", before: day(7), in: history, config: config))
    XCTAssertNil(
      TemplateHistory.lastSession(
        of: "Fly", template: nil, before: day(7), in: [], config: config))
    let all = TemplateHistory.lastSessions(
      for: dayOne, before: day(7), in: history, config: config)
    XCTAssertEqual(Set(all.keys), ["Bench"])

    // The card for a never-done exercise with no start weight shows no weight and cannot log.
    var logger = SetLogger(template: dayOne, startedAt: day(7), history: history, config: config)
    logger.log(at: day(7, minute: 1))
    logger.log(at: day(7, minute: 2))
    logger.toggleBodyweight()
    logger.log(at: day(7, minute: 3))
    XCTAssertEqual(logger.exercise?.name, "Fly")
    XCTAssertNil(logger.lastNumbers)
    XCTAssertNil(logger.pounds)
    XCTAssertEqual(logger.reps, 10)
    XCTAssertFalse(logger.canLog)
    logger.stepWeight(up: true)
    XCTAssertTrue(logger.canLog, "a weight was set")
  }
}
