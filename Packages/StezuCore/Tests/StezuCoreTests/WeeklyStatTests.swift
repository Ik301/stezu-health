import Foundation
import StezuCore
import XCTest

final class WeeklyStatTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  /// A day of January 2026 at `hour`. Monday the 5th starts the test week.
  private func day(_ day: Int, hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
  }

  func testCoverageCountsDaysWithData() async throws {
    let week = WeeklyStats.week(containing: day(11), calendar: calendar)
    XCTAssertEqual(week.start, day(5, hour: 0), "the week starts Monday")
    XCTAssertEqual(week.end, day(12, hour: 0))

    // Steps: daily totals Health merged; the Sunday before and the next Monday are outside.
    var totals: [Date: Double] = [day(4, hour: 0): 20_000, day(12, hour: 0): 20_000]
    for (offset, steps) in [6000.0, 8000, 7000, 9000, 5000, 7000].enumerated() {
      totals[day(5 + offset, hour: 0)] = steps
    }
    let steps = WeeklyStats.meanPerDay(totals, in: week)
    XCTAssertEqual(steps.value, 7000)
    XCTAssertEqual(steps.coverage, 6)
    XCTAssertEqual(steps.confidence.level, .high)
    XCTAssertEqual(steps.confidence.reason, "6 of 7 days with data")

    // Resting HR: each day's readings are averaged first, so two readings on one day count once.
    let resting = [(5, 58.0), (5, 62), (6, 57), (8, 60), (3, 90)].map {
      HealthSample(
        type: .restingHeartRate, date: day($0.0), sourceName: "Watch", value: $0.1)
    }
    let store = FakeHealthStore(samples: resting)
    let local = WeeklyStats.week(containing: day(11))
    let daily = try await store.dailyValues(of: .restingHeartRate, in: local)
    XCTAssertEqual(daily.values.sorted(), [57, 60, 60], "day 5's two readings average to 60")
    let heart = WeeklyStats.meanPerDay(daily, in: local)
    XCTAssertEqual(heart.value, 59)
    XCTAssertEqual(heart.coverage, 3)
    XCTAssertEqual(heart.confidence.level, .medium)

    // HRV: the median of every reading this week; coverage is the reading count.
    let hrv = [(5, 38.0), (6, 61), (7, 47), (7, 55), (9, 42), (2, 99)].map {
      HealthSample(
        type: .heartRateVariability, date: day($0.0), sourceName: "Watch", value: $0.1)
    }
    let median = WeeklyStats.median(hrv, in: week)
    XCTAssertEqual(median.value, 47)
    XCTAssertEqual(median.coverage, 5)
    XCTAssertEqual(median.confidence.reason, "5 samples this week")
  }

  func testMedianOfPercentReadings() async {
    let week = WeeklyStats.week(containing: day(11), calendar: calendar)

    // Blood oxygen: Health stores fractions; the median reads as a percent; coverage counts
    // readings this week, not the Saturday before.
    let oxygen = [(3, 0.90), (5, 0.97), (6, 0.95), (7, 0.98), (8, 0.96), (9, 0.97), (10, 0.99)]
      .map {
        HealthSample(type: .oxygenSaturation, date: day($0.0), sourceName: "Strap", value: $0.1)
      }
    let percent = WeeklyStats.median(oxygen, in: week, scale: 100)
    XCTAssertEqual(percent.value ?? 0, 97, accuracy: 0.001)
    XCTAssertEqual(percent.coverage, 6)
    XCTAssertEqual(percent.confidence.reason, "6 samples this week")

    // Respiratory rate: the median of every reading; two readings in one night count one night,
    // and a reading Monday 03:00 belongs to the night ending Monday.
    let breaths = [(5, 3, 14.0), (5, 4, 15.0), (6, 3, 14.6), (8, 2, 13.8), (12, 3, 20.0)].map {
      HealthSample(
        type: .respiratoryRate, date: day($0.0, hour: $0.1), sourceName: "Strap", value: $0.2)
    }
    let nightly = WeeklyStats.nightlyMedian(breaths, in: week, calendar: calendar)
    XCTAssertEqual(nightly.value ?? 0, 14.3, accuracy: 0.001)
    XCTAssertEqual(nightly.coverage, 3)
    XCTAssertEqual(nightly.confidence.reason, "3 of 7 nights with data")

    // Absent is not zero.
    let none = WeeklyStats.nightlyMedian([], in: week, calendar: calendar)
    XCTAssertNil(none.value)
    XCTAssertEqual(none.coverage, 0)

    // Temperature falls back to wrist temperature only when no body temperature exists.
    let wrist = [5, 6].map {
      HealthSample(type: .wristTemperature, date: day($0, hour: 3), sourceName: "Watch", value: 97)
    }
    let store = FakeHealthStore(samples: oxygen + breaths + wrist)
    let health = await WeeklyHealth.load(from: store, now: day(11), calendar: calendar)
    XCTAssertEqual(health.bloodOxygen.coverage, 6)
    XCTAssertEqual(health.respiratoryRate.coverage, 3)
    XCTAssertEqual(health.temperature.value, 97)
    XCTAssertEqual(health.temperature.coverage, 2)
  }

  func testNoDataIsAbsentNotZero() async {
    let week = WeeklyStats.week(containing: day(11), calendar: calendar)
    let stats = [
      WeeklyStats.meanPerDay([:], in: week),
      WeeklyStats.meanPerDay([:], in: week, of: "of 7 nights with data"),
      WeeklyStats.median([], in: week),
      WeeklyStats.sleep([], in: week, calendar: calendar),
    ]
    for stat in stats {
      XCTAssertNil(stat.value, "no data must be absent, not 0")
      XCTAssertEqual(stat.coverage, 0)
      XCTAssertEqual(stat.confidence.level, .low)
      XCTAssertEqual(stat.confidence.reason, HealthSources.deniedHint)
    }

    // A denied or empty store reads the same: every metric absent.
    let health = await WeeklyHealth.load(from: FakeHealthStore(), now: day(11))
    for stat in [
      health.steps, health.sleep, health.hrv, health.restingHeartRate, health.bloodOxygen,
      health.respiratoryRate, health.temperature,
    ] {
      XCTAssertNil(stat.value)
      XCTAssertEqual(stat.coverage, 0)
    }
  }

  /// A logged meal of one made-up item at `day` and `hour`; nil `kcal` is an unknown range.
  private func meal(_ day: Int, hour: Int = 12, kcal: (Double, Double)?, protein: (Double, Double))
    throws -> LoggedMeal
  {
    let range = kcal.map { #"{"low": \#($0.0), "high": \#($0.1)}"# } ?? "null"
    let items = try PhotoMatchClient.decode(
      Data(
        #"""
        {"meal_id": "m", "items": [{"item_id": "a", "name": "Bowl", "servings": 1,
         "kcal": \#(range), "protein_g": {"low": \#(protein.0), "high": \#(protein.1)}}]}
        """#.utf8)
    ).items
    return LoggedMeal(id: UUID(), loggedAt: self.day(day, hour: hour), items: items)
  }

  /// S-023: the Food row's range is the mean of each logged day's low and high totals.
  func testRangeMeanOverLoggedDays() throws {
    let week = WeeklyStats.week(containing: day(11), calendar: calendar)
    let meals = [
      // Monday: two meals, summed into one day of 1200-1600 kcal and 60-80 g.
      try meal(5, hour: 8, kcal: (500, 700), protein: (20, 30)),
      try meal(5, hour: 19, kcal: (700, 900), protein: (40, 50)),
      try meal(6, kcal: (700, 900), protein: (40, 50)),
      try meal(7, kcal: (1200, 1600), protein: (60, 80)),
      try meal(9, kcal: (700, 900), protein: (40, 50)),
      try meal(10, kcal: (1200, 1600), protein: (60, 80)),
      // The Sunday before and the next Monday are outside the week.
      try meal(4, kcal: (3000, 4000), protein: (200, 300)),
      try meal(12, kcal: (3000, 4000), protein: (200, 300)),
    ]
    let food = WeeklyIntake.food(meals, in: week, calendar: calendar)
    XCTAssertEqual(food.loggedDays, 5)
    XCTAssertEqual(food.kcal.value, FoodRange(low: 1000, high: 1320))
    XCTAssertEqual(food.protein.value, FoodRange(low: 52, high: 68))
    XCTAssertEqual(food.kcal.coverage, 5)
    XCTAssertEqual(food.kcal.confidence, Confidence(level: .high, reason: "logged 5 of 7 days"))

    // A day with an unknown item is logged but has no known total, so it leaves the kcal mean.
    let unknown = try meals + [meal(8, kcal: nil, protein: (10, 20))]
    let partial = WeeklyIntake.food(unknown, in: week, calendar: calendar)
    XCTAssertEqual(partial.loggedDays, 6)
    XCTAssertEqual(partial.kcal.value, FoodRange(low: 1000, high: 1320))
    XCTAssertEqual(partial.kcal.coverage, 5)
    XCTAssertEqual(partial.kcal.confidence.reason, "logged 6 of 7 days, 1 with an unknown item")
    XCTAssertEqual(partial.protein.coverage, 6)

    // No meals this week: absent, never 0.
    let none = WeeklyIntake.food(
      [try meal(4, kcal: (500, 600), protein: (1, 2))], in: week, calendar: calendar)
    XCTAssertEqual(none.loggedDays, 0)
    XCTAssertNil(none.kcal.value)
    XCTAssertNil(none.protein.value)
    XCTAssertEqual(none.kcal.confidence.level, .low)
  }

  /// S-023: Stezu sessions and Health workouts in one list, newest first; the copy Finish wrote
  /// to Health and a session kept in two stores each show once.
  func testWorkoutsMergeSourcesWithoutDuplicates() {
    let week = WeeklyStats.week(containing: day(11), calendar: calendar)
    func session(_ day: Int, sets: Int) -> WorkoutSession {
      var session = WorkoutSession(startedAt: self.day(day, hour: 18), templateKey: "day-1")
      for index in 0..<sets {
        session.logSet(
          "Bench press", pounds: 60, reps: 8, at: session.startedAt + Double(index) * 120)
      }
      return session
    }
    let stezu = [
      session(5, sets: 3), session(8, sets: 1), session(5, sets: 3), session(3, sets: 2),
    ]
    let health = [
      // Finish's copy of Monday's session, a few seconds off.
      HealthSample(
        type: .workout, date: day(5, hour: 18) + 5, sourceName: "Stezu",
        sourceBundleID: WeeklyWeight.stezuBundleID),
      HealthSample(type: .workout, date: day(10, hour: 9), sourceName: "Example Watch"),
      HealthSample(type: .workout, date: day(10, hour: 9) + 20, sourceName: "Example Phone"),
      HealthSample(type: .workout, date: day(4, hour: 9), sourceName: "Example Watch"),
      HealthSample(type: .stepCount, date: day(7, hour: 9), sourceName: "Phone", value: 100),
    ]
    let merged = WeeklyIntake.workouts(stezu: stezu, health: health, in: week)
    XCTAssertEqual(
      merged,
      [
        WeekWorkout(start: day(10, hour: 9), source: .health, detail: "Example Watch"),
        WeekWorkout(start: day(8, hour: 18), source: .stezu, detail: "1 set"),
        WeekWorkout(start: day(5, hour: 18), source: .stezu, detail: "3 sets"),
      ])
    XCTAssertEqual(WeeklyIntake.workouts(stezu: [], health: [], in: week), [])
  }
}
