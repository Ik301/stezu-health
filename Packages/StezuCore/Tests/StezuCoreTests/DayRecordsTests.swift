import Foundation
import XCTest

@testable import StezuCore

final class DayRecordsTests: XCTestCase {
  private let calendar = Calendar.current

  /// A day of January 2026 at `hour` (minutes after it) in the device's calendar.
  private func day(_ day: Int, hour: Int, minute: Int = 0) -> Date {
    let first = calendar.date(
      from: DateComponents(year: 2026, month: 1, day: 1, hour: hour, minute: minute))!
    return calendar.date(byAdding: .day, value: day - 1, to: first)!
  }

  private func sample(
    _ type: HealthType, _ date: Date, _ value: Double? = nil, from source: String = "Phone"
  ) -> HealthSample {
    HealthSample(
      type: type, date: date, sourceName: source,
      sourceBundleID: source == "Stezu" ? WeeklyWeight.stezuBundleID : "example.\(source)",
      value: value)
  }

  private func meal(_ date: Date, kcal: (Double, Double), protein: (Double, Double)?)
    -> LoggedMeal
  {
    let item = MatchedItem(
      itemId: "x", name: "Grain Bowl", hall: nil, halls: nil, brand: nil, serving: nil,
      servings: 1, confidence: nil, rough: nil, kcal: FoodRange(low: kcal.0, high: kcal.1),
      proteinG: protein.map { FoodRange(low: $0.0, high: $0.1) })
    return LoggedMeal(id: UUID(), loggedAt: date, items: [item])
  }

  func testDayGathersRecordsWithSources() async throws {
    var session = WorkoutSession(startedAt: day(5, hour: 18), templateKey: "day-1")
    session.logSet("Bench press", pounds: 60, reps: 8, at: day(5, hour: 18, minute: 2))
    session.logSet("Bench press", pounds: 60, reps: 7, at: day(5, hour: 18, minute: 4))
    session.logSet("Pull-up", pounds: nil, reps: 6, at: day(5, hour: 18, minute: 6))
    var tuesday = WorkoutSession(startedAt: day(6, hour: 18))
    tuesday.logSet("Squat", pounds: 100, reps: 5, at: day(6, hour: 18, minute: 2))
    let store = FakeHealthStore(
      samples: [
        sample(.bodyMass, day(5, hour: 7), 170.6, from: "Stezu"),
        sample(.bodyMass, day(5, hour: 8), 150, from: "Strap"),
        sample(.bodyMass, day(6, hour: 7), 170.4, from: "Stezu"),
        // Finish's copy of the Stezu session, and a watch run.
        sample(.workout, day(5, hour: 18), from: "Stezu"),
        sample(.workout, day(5, hour: 7, minute: 30), from: "Watch"),
        sample(.heartRateVariability, day(5, hour: 6), 38.4),
        sample(.heartRateVariability, day(4, hour: 6), 61),
        sample(.stepCount, day(5, hour: 9), 4000), sample(.stepCount, day(5, hour: 18), 3500),
      ],
      sleep: [
        (start: day(4, hour: 23), end: day(5, hour: 3), stage: .asleepCore),
        (start: day(5, hour: 3), end: day(5, hour: 6, minute: 20), stage: .asleepDeep),
        (start: day(5, hour: 6, minute: 20), end: day(5, hour: 7), stage: .awake),
      ])
    let meals = [
      meal(day(5, hour: 12), kcal: (700, 900), protein: (40, 50)),
      meal(day(5, hour: 19), kcal: (500, 700), protein: nil),
      meal(day(6, hour: 12), kcal: (100, 200), protein: (1, 2)),
    ]

    let records = await DayRecords.load(
      day(5, hour: 15), from: store, meals: meals, sessions: [session, session, tuesday],
      calendar: calendar)

    XCTAssertEqual(
      records.map(\.kind),
      [.weighIn, .weighIn, .meal, .meal, .workout, .workout, .sleep, .hrv, .steps],
      "everything on Monday once, in story order; Tuesday's records left out")
    XCTAssertEqual(
      records.map(\.source),
      [
        "Stezu", "Strap", "Stezu", "Stezu", "Watch", "Stezu", "Health", "Phone", "Phone",
      ])
    XCTAssertEqual(
      records.map(\.detail),
      [
        "170.6 lb", "150.0 lb", "Grain Bowl: 700-900 kcal, 40-50 g protein",
        "Grain Bowl: 500-700 kcal, -- g protein", "--",
        "Bench press 60 lb x 8, 60 lb x 7; Pull-up bodyweight x 6", "7h 20m asleep", "38 ms",
        "7500",
      ])
    XCTAssertEqual(records[0].owner, .weighIn(day(5, hour: 7)), "Stezu's weigh-in is its own")
    XCTAssertEqual(records[1].owner, .health, "a strap's weight is read-only")
    XCTAssertEqual(records[2].owner, .meal(meals[0].id))
    XCTAssertEqual(records[5].owner, .session(day(5, hour: 18)))
    XCTAssertEqual(
      records.map(\.isStezu), [true, false, true, true, false, true, false, false, false])

    // Deleting the weigh-in removes only Stezu's sample.
    try await store.deleteBodyMass(at: day(5, hour: 7))
    let after = await DayRecords.load(
      day(5, hour: 15), from: store, meals: [], sessions: [], calendar: calendar)
    XCTAssertEqual(after.filter { $0.kind == .weighIn }.map(\.source), ["Strap"])

    // A day with nothing recorded lists nothing, not zeros.
    let empty = await DayRecords.load(
      day(20, hour: 12), from: store, meals: meals, sessions: [session], calendar: calendar)
    XCTAssertEqual(empty, [])
  }
}
