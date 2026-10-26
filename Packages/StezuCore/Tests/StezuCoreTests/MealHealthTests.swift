import StezuCore
import XCTest

/// S-018: a logged meal goes to Health as one food entry. All values are made up (D-034).
final class MealHealthTests: XCTestCase {
  private let loggedAt = Date(timeIntervalSince1970: 1_800_000_000)

  private func meal() throws -> LoggedMeal {
    let items = try PhotoMatchClient.decode(
      Data(
        #"""
        {"meal_id": "m", "items": [
         {"item_id": "a", "name": "Rice", "servings": 1,
          "kcal": {"low": 150, "high": 250}, "protein_g": {"low": 3, "high": 5}},
         {"item_id": "b", "name": "Beans", "servings": 1,
          "kcal": {"low": 100, "high": 140}, "protein_g": {"low": 6, "high": 10}}]}
        """#.utf8)
    ).items
    return LoggedMeal(id: UUID(), loggedAt: loggedAt, items: items)
  }

  /// Records what was on the phone each time the meal was saved, in order.
  private actor Saves {
    var meals: [LoggedMeal] = []
    func add(_ meal: LoggedMeal) { meals.append(meal) }
  }

  func testWritesMidpointsWithRangeMetadata() async throws {
    let health = FakeHealthStore()
    let saves = Saves()
    let meal = try meal()
    let logged = try await MealHealth.log(meal, health: health) { await saves.add($0) }
    XCTAssertEqual(logged.inHealth, true)
    XCTAssertEqual(logged.items, meal.items)

    // Saved on the phone before the write, then again with its Health state.
    let saved = await saves.meals
    XCTAssertEqual(saved.map(\.inHealth), [nil, true])
    XCTAssertEqual(saved.last, logged)

    // One entry: the totals' midpoints, the low and high as metadata, the meal id as sync id.
    let foods = await health.savedFoods
    XCTAssertEqual(foods.count, 1)
    let entry = try XCTUnwrap(foods.first)
    XCTAssertEqual(entry.syncIdentifier, meal.id.uuidString)
    XCTAssertEqual(entry.date, loggedAt)
    let kcal = try XCTUnwrap(entry.kcal)
    let protein = try XCTUnwrap(entry.proteinG)
    XCTAssertEqual(kcal.midpoint, 320)
    XCTAssertEqual(protein.midpoint, 12)
    XCTAssertEqual(
      kcal.metadata(FoodEntry.kcalKeys), ["stezu_kcal_low": 250, "stezu_kcal_high": 390])
    XCTAssertEqual(
      protein.metadata(FoodEntry.proteinKeys),
      ["stezu_protein_g_low": 9, "stezu_protein_g_high": 15])

    // Writing the same meal again replaces its entry; Undo removes it.
    _ = try await MealHealth.log(meal, health: health) { _ in }
    let again = await health.savedFoods
    XCTAssertEqual(again.count, 1)
    try await health.deleteFood(syncIdentifier: meal.id.uuidString)
    let afterUndo = await health.savedFoods
    XCTAssertTrue(afterUndo.isEmpty)
  }

  func testDeniedWriteKeepsMeal() async throws {
    let health = FakeHealthStore()
    await health.setFailsWrites(true)
    let saves = Saves()
    let meal = try meal()
    let logged = try await MealHealth.log(meal, health: health) { await saves.add($0) }
    XCTAssertEqual(logged.inHealth, false)
    XCTAssertEqual(logged.id, meal.id)
    XCTAssertEqual(logged.items, meal.items, "a denied write dropped the meal's items")
    let saved = await saves.meals
    XCTAssertEqual(saved.map(\.inHealth), [nil, false], "the meal was not kept on the phone")
    let foods = await health.savedFoods
    XCTAssertTrue(foods.isEmpty)

    // A failed local save stops before Health: nothing is written.
    struct DiskFull: Error {}
    let open = FakeHealthStore()
    do {
      _ = try await MealHealth.log(meal, health: open) { _ in throw DiskFull() }
      XCTFail("a failed local save did not throw")
    } catch {}
    let none = await open.savedFoods
    XCTAssertTrue(none.isEmpty, "the meal reached Health without a local copy")
  }
}
