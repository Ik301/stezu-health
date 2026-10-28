import Foundation
import StezuCore
import XCTest

/// S-039: the 7 values a This week Sparkline draws, Monday to Sunday, taken from the metric's
/// history as its detail is. A day without data stays nil (a dashed slot, never a near-zero
/// tick), a rest day's 0 stays 0, and a night is named by the day it ends on.
final class SparklineTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  /// Minutes from midnight of January `day`, 2026 (negative is the evening before). Monday the
  /// 5th starts the week of Sunday the 11th.
  private func at(_ day: Int, _ minutes: Double = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 1, day: day))! + minutes * 60
  }

  private func week(_ metric: Metric, _ daily: [Date: Double], now: Date) -> [Double?] {
    ChartSeries.sparkline(
      MetricHistory.history(metric, daily: daily, now: now, calendar: calendar) {
        WeeklyStats.meanPerDay(daily, in: $0)
      })
  }

  func testWeekSeriesKeepsGapsAsNil() {
    let now = at(9, 12 * 60)  // Friday noon
    // Last Sunday, then Monday, Wednesday and Friday; Saturday and Sunday are to come.
    let steps = week(.steps, [at(4): 9000, at(5): 12000, at(7): 3000, at(9): 6000], now: now)
    XCTAssertEqual(steps, [12000, nil, 3000, nil, 6000, nil, nil], "gaps stay nil, never 0")

    // Workouts: a day up to now without a session is a rest day, a real 0; days to come are gaps.
    let set = WorkoutSet(pounds: 100, reps: 8, loggedAt: at(6, 17 * 60))
    let session = WorkoutSession(
      startedAt: at(6, 17 * 60), exercises: [ExerciseLog(exercise: "Squat", sets: [set, set])])
    let sets = ChartSeries.sparkline(
      MetricHistory.workouts([session], now: now, calendar: calendar))
    XCTAssertEqual(sets.count, 7)
    XCTAssertEqual(sets[0], 0, "Monday was a rest day")
    XCTAssertEqual(sets[1], 2, "Tuesday's working sets")
    XCTAssertEqual(sets[4], 0, "today so far is a rest day")
    XCTAssertNil(sets[5], "Saturday is to come")
    XCTAssertNil(sets[6])
  }

  func testSleepNightsLabeledByWakeDay() {
    let now = at(11, 12 * 60)  // Sunday noon
    let intervals: [SleepInterval] = [
      // Sunday 23:00 the week before to Monday 07:00: Monday's night.
      (start: at(5, -60), end: at(5, 7 * 60), stage: .asleepCore),
      // Wednesday 22:30 to Thursday 06:30: Thursday's.
      (start: at(8, -90), end: at(8, 6.5 * 60), stage: .asleepCore),
      // Saturday 23:30 to Sunday 06:00: Sunday's.
      (start: at(11, -30), end: at(11, 6 * 60), stage: .asleepDeep),
    ]
    let nights = week(.sleep, SleepNights.nights(intervals, calendar: calendar), now: now)
    XCTAssertEqual(nights[0], 8 * 3600, "the night is named by Monday, the morning of waking")
    XCTAssertNil(nights[2], "no night ended on Wednesday")
    XCTAssertEqual(nights[3], 8 * 3600)
    XCTAssertEqual(nights[6], 6.5 * 3600)
    XCTAssertEqual(nights.compactMap { $0 }.count, 3, "the other days are dashed slots")
  }
}
