import Foundation
import StezuCore
import XCTest

/// S-042: the series WeekBars draws. Absent weeks stay nil (a dashed slot, never 0), and food's
/// bands add lows and highs separately.
final class ChartSeriesTests: XCTestCase {
  private let calendar = Calendar.current

  /// A day of January 2026 (0 and below roll back into December); Monday the 5th starts the
  /// current week of Sunday the 11th.
  private func day(_ day: Int, hour: Int = 9) -> Date {
    let first = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour))!
    return calendar.date(byAdding: .day, value: day - 1, to: first)!
  }

  func testWeekBarsKeepAbsentWeeksAsNil() {
    let now = day(11, hour: 12)
    // Steps on two days this week and one day three weeks back; every other week is empty.
    let daily = [day(5, hour: 0): 6000.0, day(6, hour: 0): 8000, day(-15, hour: 0): 4000]
    let history = MetricHistory.history(.steps, daily: daily, now: now, calendar: calendar) {
      WeeklyStats.meanPerDay(daily, in: $0)
    }
    let bars = ChartSeries.weekBars(history)
    XCTAssertEqual(bars.count, 8)
    XCTAssertEqual(bars.last?.start, day(5, hour: 0), "the current week is last, on the right")
    XCTAssertEqual(bars.first?.start, day(-44, hour: 0), "the oldest week is first, on the left")
    XCTAssertEqual(bars[7].value, 7000)
    XCTAssertEqual(bars[7].coverage, 2)
    XCTAssertEqual(bars[4].value, 4000, "the week of Dec 15")
    XCTAssertEqual(bars[4].coverage, 1)
    for index in [0, 1, 2, 3, 5, 6] {
      XCTAssertNil(bars[index].value, "week \(index) has no data: absent, not 0")
      XCTAssertEqual(bars[index].coverage, 0)
      XCTAssertNil(bars[index].band)
    }
  }

  func testRangeBandsSumLowsAndHighsSeparately() throws {
    let now = day(11, hour: 12)
    let meals = [
      // Monday: 500-700 and 300-500 kcal, one day of 800-1200 kcal and 50-70 g.
      try meal(5, kcal: (500, 700), protein: (30, 40)),
      try meal(5, hour: 18, kcal: (300, 500), protein: (20, 30)),
      // Wednesday: 400-600 kcal, so the week's mean is 600-900 kcal.
      try meal(7, kcal: (400, 600), protein: (10, 30)),
      // Two weeks back: one meal.
      try meal(-4, kcal: (1000, 1100), protein: (40, 60)),
    ]
    let energy = ChartSeries.rangeBands(meals, \.kcal, now: now, calendar: calendar)
    XCTAssertEqual(energy.count, 8)
    XCTAssertEqual(energy[7].start, day(5, hour: 0))
    XCTAssertEqual(energy[7].band, FoodRange(low: 600, high: 900))
    XCTAssertEqual(energy[7].value, 750, "the midpoint")
    XCTAssertEqual(energy[7].coverage, 2)
    XCTAssertEqual(energy[5].band, FoodRange(low: 1000, high: 1100))
    XCTAssertNil(energy[6].band, "no meals last week")
    XCTAssertNil(energy[6].value, "absent, not 0")
    XCTAssertEqual(energy[6].coverage, 0)

    let protein = ChartSeries.rangeBands(meals, \.protein, now: now, calendar: calendar)
    XCTAssertEqual(protein[7].band, FoodRange(low: 30, high: 50), "(50 + 10) / 2, (70 + 30) / 2")
    XCTAssertEqual(protein[7].value, 40)

    // The detail's weeks and days: Monday's midpoint, Tuesday absent, and two days with data.
    let food = MetricHistory.food(meals, now: now, calendar: calendar)
    XCTAssertEqual(food.weeks[0].days.map(\.value), [1000, nil, 500, nil, nil, nil, nil])
    XCTAssertEqual(food.weeks[0].stat.coverage, 2)
    XCTAssertNil(food.weeks[1].stat.value, "no meals last week: absent, not 0")
  }

  /// A logged meal of one made-up item at `day` and `hour`.
  private func meal(
    _ day: Int, hour: Int = 12, kcal: (Double, Double), protein: (Double, Double)
  ) throws -> LoggedMeal {
    let items = try PhotoMatchClient.decode(
      Data(
        #"""
        {"meal_id": "m", "items": [{"item_id": "a", "name": "Bowl", "servings": 1,
         "kcal": {"low": \#(kcal.0), "high": \#(kcal.1)},
         "protein_g": {"low": \#(protein.0), "high": \#(protein.1)}}]}
        """#.utf8)
    ).items
    return LoggedMeal(id: UUID(), loggedAt: self.day(day, hour: hour), items: items)
  }
}
