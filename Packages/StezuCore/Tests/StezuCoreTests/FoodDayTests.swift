import StezuCore
import XCTest

/// S-019: a day's food as summed ranges, with no target. All values are made up (D-034).
final class FoodDayTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }
  private let noon = Date(timeIntervalSince1970: 1_800_014_400)  // a UTC noon

  private func meal(_ hoursAgo: Double, _ kcal: String, _ protein: String) throws -> LoggedMeal {
    let reply = #"""
      {"meal_id": "m", "items": [{"item_id": "a", "name": "Grain Bowl", "servings": 1,
       "kcal": \#(kcal), "protein_g": \#(protein)}]}
      """#
    let items = try PhotoMatchClient.decode(Data(reply.utf8)).items
    return LoggedMeal(id: UUID(), loggedAt: noon - hoursAgo * 3600, items: items)
  }

  func testTodayTotalsSumRanges() throws {
    let breakfast = try meal(4, #"{"low": 300, "high": 400}"#, #"{"low": 10, "high": 15}"#)
    let lunch = try meal(1, #"{"low": 500, "high": 700}"#, #"{"low": 30, "high": 40}"#)
    let yesterday = try meal(20, #"{"low": 900, "high": 900}"#, #"{"low": 50, "high": 50}"#)
    let pending = QueuedMeal(id: UUID(), capturedAt: noon - 1800)

    let today = FoodDay.on(
      noon, meals: [breakfast, lunch, yesterday], pending: [pending], calendar: calendar)
    XCTAssertEqual(today.kcal, FoodRange(low: 800, high: 1100))
    XCTAssertEqual(today.proteinG, FoodRange(low: 40, high: 55))
    XCTAssertEqual(today.mealCount, 2)
    XCTAssertEqual(today.meals.map(\.id), [lunch.id, breakfast.id], "newest first")
    XCTAssertEqual(today.pending.map(\.id), [pending.id])
    XCTAssertEqual(today.confidence.level, .medium, "a pending photo lowers it")

    let days = FoodDay.days(
      meals: [breakfast, lunch, yesterday], pending: [pending], calendar: calendar)
    XCTAssertEqual(days.count, 2)
    XCTAssertEqual(days.first?.day, calendar.startOfDay(for: noon), "newest day first")
    XCTAssertEqual(days.last?.kcal, FoodRange(low: 900, high: 900))
    XCTAssertEqual(days.last?.confidence.level, .high)
  }

  func testNoMealsIsAbsentNotZero() throws {
    let empty = FoodDay.on(noon, meals: [], calendar: calendar)
    XCTAssertNil(empty.kcal)
    XCTAssertNil(empty.proteinG)
    XCTAssertNil(empty.mealCount)
    XCTAssertEqual(empty.confidence.level, .low)

    // A pending photo alone logs nothing: still no total, not 0.
    let pendingOnly = FoodDay.on(
      noon, meals: [], pending: [QueuedMeal(id: UUID(), capturedAt: noon)], calendar: calendar)
    XCTAssertNil(pendingOnly.kcal)
    XCTAssertNil(pendingOnly.mealCount)

    // An item without a range makes the day's total unknown, not smaller.
    let unknown = try meal(1, "null", #"{"low": 5, "high": 8}"#)
    let known = try meal(2, #"{"low": 300, "high": 400}"#, #"{"low": 10, "high": 15}"#)
    let day = FoodDay.on(noon, meals: [unknown, known], calendar: calendar)
    XCTAssertNil(day.kcal)
    XCTAssertEqual(day.proteinG, FoodRange(low: 15, high: 23))
    XCTAssertEqual(day.mealCount, 2)
    XCTAssertTrue(FoodDay.days(meals: [], calendar: calendar).isEmpty)
  }

  func testDeletedMealLeavesTotals() throws {
    let breakfast = try meal(4, #"{"low": 300, "high": 400}"#, #"{"low": 10, "high": 15}"#)
    let lunch = try meal(1, #"{"low": 500, "high": 700}"#, #"{"low": 30, "high": 40}"#)
    let today = FoodDay.on(noon, meals: [breakfast, lunch], calendar: calendar)

    // The store lost the meal: the day is gathered again without it.
    let after = FoodDay.on(
      noon, meals: today.meals.filter { $0.id != lunch.id }, calendar: calendar)
    XCTAssertEqual(after.meals.map(\.id), [breakfast.id])
    XCTAssertEqual(after.kcal, FoodRange(low: 300, high: 400))
    XCTAssertEqual(after.proteinG, FoodRange(low: 10, high: 15))
    XCTAssertEqual(after.mealCount, 1)

    // The last meal deleted leaves no total at all, not 0.
    let none = FoodDay.on(noon, meals: [], calendar: calendar)
    XCTAssertNil(none.kcal)
    XCTAssertNil(none.mealCount)
  }

  /// Steps 3 and 4: an edit replaces the meal's Health entry; a delete removes it.
  func testEditReplacesHealthEntryAndDeleteRemovesIt() async throws {
    let health = FakeHealthStore()
    let lunch = try meal(1, #"{"low": 500, "high": 700}"#, #"{"low": 30, "high": 40}"#)
    _ = try await MealHealth.log(lunch, health: health) { _ in }

    let edited = LoggedMeal(
      id: lunch.id, loggedAt: lunch.loggedAt, items: lunch.items.map { $0.withServings(1.5) })
    let written = try await MealHealth.replace(edited, health: health) { _ in }
    XCTAssertEqual(written.inHealth, true)
    let foods = await health.savedFoods
    XCTAssertEqual(foods.count, 1, "the old entry was kept beside the edit")
    XCTAssertEqual(foods.first?.kcal, FoodRange(low: 750, high: 1050))

    let removed = await MealHealth.delete(lunch.id, health: health) { _ in }
    XCTAssertTrue(removed)
    let after = await health.savedFoods
    XCTAssertTrue(after.isEmpty)
  }
}
