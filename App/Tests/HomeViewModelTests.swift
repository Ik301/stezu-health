import StezuCore
import XCTest

@testable import StezuHealth

/// Synthetic values only: no real weights, intakes or sessions.
final class HomeViewModelTests: XCTestCase {
  private var calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()

  private func date(day: Int, hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: 2030, month: 1, day: day, hour: hour))!
  }

  private func model(hour: Int = 12) -> HomeViewModel {
    let now = date(day: 10, hour: hour)
    return HomeViewModel(calendar: calendar, now: { now })
  }

  func testThreeCardsInOrder() {
    let today = date(day: 10)
    let trendConfig = TrendWeightConfig(calendar: calendar)
    let weighIns = [WeighIn(date: today, pounds: 123.4)]
    var session = WorkoutSession(startedAt: date(day: 7))
    session.logSet("Squat", pounds: 100, reps: 5, at: date(day: 7))
    session.logSet("Squat", pounds: 110, reps: 3, at: date(day: 7))
    let inputs = HomeInputs(
      trend: TrendWeight.estimate(asOf: today, weighIns: weighIns, config: trendConfig),
      target: WeeklyTarget.evaluate(
        asOf: today, currentTarget: 2000, weighIns: weighIns, lastChange: nil,
        config: WeeklyTargetConfig(trend: trendConfig)),
      intakeTodayKcal: 850,
      lastSession: WorkoutHistory.lastSession(
        of: "Squat", before: today, in: [session],
        config: WorkoutHistoryConfig(calendar: calendar)))

    let cards = model().cards(inputs)

    XCTAssertEqual(cards.map(\.id), ["data", "food", "workout"])
    XCTAssertEqual(cards.map(\.label), ["Data", "Food", "Workout"])
    XCTAssertEqual(cards.map(\.value), ["123.4", "850 / 2000", "110 x 3"])
    XCTAssertEqual(cards[2].subtitle, "Squat, 3d ago")
    XCTAssertTrue(cards.allSatisfy { $0.confidence != nil })
  }

  func testMissingValuesShowDashes() {
    let empty = model().cards(HomeInputs())
    XCTAssertEqual(empty.map(\.value), ["--", "--", "--"])
    XCTAssertTrue(empty.allSatisfy { $0.confidence == nil })

    // Intake logged but no target yet: the missing half is "--", not 0.
    let partial = model().cards(HomeInputs(intakeTodayKcal: 600))
    XCTAssertEqual(partial[1].value, "600 / --")
    XCTAssertEqual(partial[0].value, "--")
    XCTAssertFalse(partial.contains { $0.value == "0" })
  }

  func testTimeOfDayPicksInvertedCard() {
    XCTAssertEqual(model(hour: 3).invertedCardID(), "food")
    XCTAssertEqual(model(hour: 5).invertedCardID(), "data")
    XCTAssertEqual(model(hour: 10).invertedCardID(), "data")
    XCTAssertEqual(model(hour: 11).invertedCardID(), "food")
    XCTAssertEqual(model(hour: 17).invertedCardID(), "workout")
    XCTAssertEqual(model(hour: 21).invertedCardID(), "food")

    var custom = model(hour: 7)
    custom.schedule = [(6, "workout"), (12, "data")]
    XCTAssertEqual(custom.invertedCardID(), "workout")
  }
}
