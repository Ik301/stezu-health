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

  /// A week of 2030 (Monday the 7th to Sunday the 13th), seen on Sunday noon: weigh-ins on 5 days
  /// plus one the week before, two meals today and one yesterday, a Stezu session Monday that
  /// Health also has, and a Health run Saturday.
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
    return HomeInputs(
      weight: WeeklyWeight.week(of: weighIns, now: now, calendar: calendar),
      food: FoodDay.on(now, meals: meals, calendar: calendar),
      workouts: WeeklyIntake.workouts(
        stezu: [session], health: health,
        in: WeeklyStats.week(containing: now, calendar: calendar)),
      nextTemplate: "Day 1")
  }

  func testThreeCardsInOrder() throws {
    let cards = model().cards(try filledInputs())

    XCTAssertEqual(cards.map(\.id), ["data", "food", "workout"])
    XCTAssertEqual(cards.map(\.label), ["Data", "Food", "Workout"])
    XCTAssertEqual(cards.map(\.value), ["150.0", "1200-1600", "2"])
    XCTAssertTrue(cards.allSatisfy { $0.confidence != nil })
  }

  func testCardsShowTrackingNumbersWithoutTarget() throws {
    let cards = model().cards(try filledInputs())

    XCTAssertEqual(
      cards.map(\.subtitle),
      [
        "Trend weight, lb. Weigh-ins 5 of 7",
        "Today, kcal. 60-80 g protein, 2 meals",
        "Sessions this week. Next: Day 1",
      ])
    XCTAssertEqual(cards[2].confidence?.reason, "1 from Stezu, 1 from Health")
    // Tracking only (D-032): no target, remaining amount or score on any card.
    for card in cards {
      let text = "\(card.label) \(card.subtitle) \(card.value)".lowercased()
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
      empty.map(\.subtitle),
      [
        "Trend weight, lb. Weigh-ins --",
        "Today, kcal. -- g protein, -- meals",
        "Sessions this week. Next: --",
      ])

    // Read, but nothing recorded: a week with no weigh-in, a day with no meal and no session
    // this week still show "--", not 0.
    let now = date(day: 13)
    let none = model().cards(
      HomeInputs(
        weight: WeeklyWeight.week(of: [], now: now, calendar: calendar),
        food: FoodDay.on(now, meals: [], calendar: calendar), workouts: [],
        nextTemplate: "Day 1"))
    XCTAssertEqual(none.map(\.value), ["--", "--", "--"])
    XCTAssertTrue(none.allSatisfy { $0.confidence == nil })

    // Food logged, nothing else: the other cards stay "--".
    var partial = HomeInputs()
    partial.food = try filledInputs().food
    let cards = model().cards(partial)
    XCTAssertEqual(cards.map(\.value), ["--", "1200-1600", "--"])
    XCTAssertFalse(cards.contains { $0.value == "0" || $0.subtitle.contains(" 0 ") })
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
