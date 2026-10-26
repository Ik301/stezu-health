import Foundation
import XCTest

@testable import StezuCore

final class WeeklyHistoryTests: XCTestCase {
  /// Gregorian in UTC with Sunday as the first weekday, so the Monday start must come from
  /// WeeklyHistory itself. All dates are synthetic.
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 1
    return calendar
  }

  private func date(_ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
  }

  private func session(_ start: Date, _ sets: [(String, Double?)]) -> WorkoutSession {
    var session = WorkoutSession(startedAt: start, templateKey: "day-1")
    for (index, set) in sets.enumerated() {
      session.logSet(set.0, pounds: set.1, reps: 8, at: start + Double(index + 1) * 60)
    }
    return session
  }

  func testWeekRunsMondayToSunday() {
    // 2026-10-19 is a Monday and 2026-10-25 a Sunday.
    let monday = session(date(10, 19, 0), [("Squat", 100)])
    let sunday = session(date(10, 25, 23), [("Squat", 100)])
    let nextMonday = session(date(10, 26, 7), [("Squat", 105)])
    let weeks = WeeklyHistory.weeks([monday, nextMonday, sunday], calendar: calendar)

    XCTAssertEqual(weeks.count, 2)
    XCTAssertEqual(weeks.map(\.start), [date(10, 26, 0), date(10, 19, 0)], "newest week first")
    XCTAssertEqual(weeks[1].end, date(10, 25, 0))
    XCTAssertEqual(weeks[1].sessions, [sunday, monday], "newest session first")
    XCTAssertEqual(weeks[0].sessions, [nextMonday])
  }

  func testWorkingSetsPerWeek() {
    let first = session(date(10, 20), [("Bench press", 60), ("Bench press", 60), ("Row", 70)])
    let bodyweight = session(date(10, 22), [("Pull-up", nil), ("Pull-up", nil)])
    let older = session(date(10, 6), [("Bench press", 55)])
    let weeks = WeeklyHistory.weeks([older, first, bodyweight], calendar: calendar)

    // The week of 2026-10-12 has no session, so it has no row rather than a row of 0.
    XCTAssertEqual(weeks.map(\.start), [date(10, 19, 0), date(10, 5, 0)])
    XCTAssertEqual(weeks.map(\.workingSets), [5, 1])
    XCTAssertFalse(weeks.contains { $0.workingSets == 0 })
    XCTAssertTrue(WeeklyHistory.weeks([], calendar: calendar).isEmpty)
  }

  func testExerciseSessionsNewestFirst() {
    let first = session(date(10, 6), [("Bench press", 55)])
    let second = session(date(10, 20), [("Row", 70)])
    let third = session(date(10, 22), [("Bench press", 60)])
    let bench = WeeklyHistory.sessions(with: "Bench press", in: [first, third, second])
    XCTAssertEqual(bench, [third, first])
    XCTAssertTrue(WeeklyHistory.sessions(with: "Squat", in: [first]).isEmpty)
  }
}
