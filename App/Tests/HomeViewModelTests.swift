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

  private func model(day: Int = 10, hour: Int = 12) -> HomeViewModel {
    let now = date(day: day, hour: hour)
    return HomeViewModel(calendar: calendar, now: { now })
  }

  /// A week of 2030 (Monday the 7th to Sunday the 13th), seen on Sunday noon: weigh-ins on 5 days
  /// plus one the week before, two meals today and one yesterday, a Stezu session Monday that
  /// Health also has, a Health run Saturday, and two nights: 6h 30m ending Saturday and 7h 12m
  /// asleep last night among in-bed and awake stretches.
  private func filledInputs() throws -> HomeInputs {
    let now = date(day: 13)
    let weighIns = [3, 7, 8, 9, 11, 12].map {
      HealthSample(
        type: .bodyMass, date: date(day: $0, hour: 7), sourceName: "Stezu",
        sourceBundleID: WeeklyWeight.stezuBundleID, value: 150)
    }
    func meal(_ day: Int, kcal: (Int, Int), protein: (Int, Int)) throws -> LoggedMeal {
      let reply = #"""
        {"meal_id": "m", "items": [{"item_id": "x", "name": "Grain Bowl", "servings": 1,
         "kcal": {"low": \#(kcal.0), "high": \#(kcal.1)},
         "protein_g": {"low": \#(protein.0), "high": \#(protein.1)}}]}
        """#
      let items = try PhotoMatchClient.decode(Data(reply.utf8)).items
      return LoggedMeal(id: UUID(), loggedAt: date(day: day, hour: 9), items: items)
    }
    let meals = [
      try meal(13, kcal: (700, 900), protein: (40, 50)),
      try meal(13, kcal: (500, 700), protein: (20, 30)),
      try meal(12, kcal: (300, 400), protein: (10, 20)),
    ]
    var session = WorkoutSession(startedAt: date(day: 7, hour: 18), templateKey: "day-1")
    session.logSet("Squat", pounds: 100, reps: 5, at: date(day: 7, hour: 18) + 120)
    let health = [
      HealthSample(type: .workout, date: date(day: 7, hour: 18), sourceName: "Stezu"),
      HealthSample(type: .workout, date: date(day: 12, hour: 9), sourceName: "Example Watch"),
    ]
    let sleep: [SleepInterval] = [
      (date(day: 11, hour: 23), date(day: 12, hour: 5) + 30 * 60, .asleepCore),
      (date(day: 12, hour: 22), date(day: 13, hour: 7), .inBed),
      (date(day: 12, hour: 23), date(day: 13, hour: 3), .asleepCore),
      (date(day: 13, hour: 3), date(day: 13, hour: 3) + 10 * 60, .awake),
      (date(day: 13, hour: 3) + 10 * 60, date(day: 13, hour: 6) + 22 * 60, .asleepREM),
    ]
    return HomeInputs(
      sleep: SleepSummary.make(sleep, now: now, calendar: calendar),
      weight: WeeklyWeight.week(of: weighIns, now: now, calendar: calendar),
      food: FoodDay.on(now, meals: meals, calendar: calendar),
      workouts: WeeklyIntake.workouts(
        stezu: [session], health: health,
        in: WeeklyStats.week(containing: now, calendar: calendar)),
      nextTemplate: "Day 1", sets: 1)
  }

  func testThreeCardsInOrder() throws {
    let cards = model(day: 13).cards(try filledInputs())

    XCTAssertEqual(cards.map(\.id), ["data", "food", "workout"])
    XCTAssertEqual(cards.map(\.label), ["Data", "Food", "Workout"])
    XCTAssertEqual(cards.map(\.frame), ["Last night", "Today", "This week"])
    XCTAssertEqual(cards.map(\.value), ["7h 12m", "1,200–1,600", "2"])
    XCTAssertTrue(cards.allSatisfy { $0.confidence != nil })
    // The week's nights in hours, Monday first, with today (Sunday) last; Workout's dots.
    XCTAssertEqual(cards[0].bars, [nil, nil, nil, nil, nil, 6.5, 7.2])
    XCTAssertEqual(cards[0].today, 6)
    XCTAssertEqual(cards[2].dots, [true, false, false, false, false, true, false])
  }

  func testCardsShowTrackingNumbersWithoutTarget() throws {
    let cards = model(day: 13).cards(try filledInputs())

    XCTAssertEqual(
      cards.map(\.accessibilityLabel),
      [
        "Data, Last night, 7 hours 12 minutes asleep, Usual 6h 51m, Weight 150.0 lb",
        "Food, Today, 1,200–1,600 kcal, 60–80 g protein, 2 meals",
        "Workout, This week, 2 sessions (Mon, Sat), Next: Day 1, 1 set",
      ])
    XCTAssertEqual(cards[0].confidence?.reason, "median of 2 nights")
    XCTAssertEqual(cards[2].confidence?.reason, "1 from Stezu, 1 from Health")
    // Tracking only (D-032): no target, remaining amount or score on any card.
    for card in cards {
      let text = card.accessibilityLabel.lowercased()
      for word in ["target", "remaining", "left", "score", "/"] {
        XCTAssertFalse(text.contains(word), "\(card.id) shows \(word): \(text)")
      }
    }
  }

  func testMissingValuesShowDashes() throws {
    let empty = model().cards(HomeInputs())
    XCTAssertEqual(empty.map(\.value), ["--", "--", "--"])
    XCTAssertTrue(empty.allSatisfy { $0.confidence == nil })
    XCTAssertEqual(
      empty.map(\.accessibilityLabel),
      [
        "Data, Last night, --, Usual --, Weight --",
        "Food, Today, -- kcal, -- g protein, -- meals",
        "Workout, This week, -- sessions, Next: --, -- sets",
      ])
    XCTAssertEqual(empty[0].bars, Array(repeating: nil, count: 7))

    // Read, but nothing recorded: a week with no weigh-in, a day with no meal and no session
    // this week still show "--", not 0.
    let now = date(day: 13)
    let none = model().cards(
      HomeInputs(
        weight: WeeklyWeight.week(of: [], now: now, calendar: calendar),
        food: FoodDay.on(now, meals: [], calendar: calendar), workouts: [],
        nextTemplate: "Day 1"))
    XCTAssertEqual(none.map(\.value), ["--", "--", "--"])
    XCTAssertEqual(none[2].dots, [false, false, false, false])
    XCTAssertTrue(none.allSatisfy { $0.confidence == nil })

    // Food logged, nothing else: the other cards stay "--".
    var partial = HomeInputs()
    partial.food = try filledInputs().food
    let cards = model().cards(partial)
    XCTAssertEqual(cards.map(\.value), ["--", "1,200–1,600", "--"])
    XCTAssertFalse(cards.contains { $0.value == "0" || $0.accessibilityLabel.contains(" 0 ") })
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

    // A workout in progress inverts the Workout card at any hour (S-037).
    XCTAssertEqual(model(hour: 5).invertedCardID(workoutInProgress: true), "workout")
  }
}
