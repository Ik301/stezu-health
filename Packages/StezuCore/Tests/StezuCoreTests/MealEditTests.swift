import StezuCore
import XCTest

/// S-015: the item list after a photo or a pick. All values are made up (D-034).
final class MealEditTests: XCTestCase {
  private func match() throws -> PhotoMatch {
    try PhotoMatchClient.decode(
      Data(
        #"""
        {"meal_id": "m", "items": [
         {"item_id": "a", "name": "Rice", "serving": "4 oz", "servings": 1.5,
          "kcal": {"low": 150, "high": 300}, "protein_g": {"low": 3, "high": 6}},
         {"item_id": "b", "name": "Beans", "servings": 1,
          "kcal": {"low": 100, "high": 140}, "protein_g": {"low": 6, "high": 8}},
         {"item_id": "c", "name": "Soup", "kcal": {"low": 50, "high": null}}]}
        """#.utf8))
  }

  private func item(_ name: String, kcal: Double, protein: Double) throws -> MatchedItem {
    try PhotoMatchClient.decode(
      Data(
        #"""
        {"meal_id": "x", "items": [{"item_id": "\#(name)", "name": "\#(name)", "servings": 1,
         "kcal": {"low": \#(kcal), "high": \#(kcal * 2)},
         "protein_g": {"low": \#(protein), "high": \#(protein * 2)}}]}
        """#.utf8)
    ).items[0]
  }

  func testHalfServingStepsRecomputeRanges() throws {
    var edit = MealEdit(try match())
    XCTAssertNil(edit.totalKcal, "the soup has no kcal high end, so the total is unknown")
    edit.step(0, up: true)
    XCTAssertEqual(edit.items[0].servings, 2)
    XCTAssertEqual(edit.items[0].kcal, FoodRange(low: 200, high: 400))
    XCTAssertEqual(edit.items[0].proteinG, FoodRange(low: 4, high: 8))
    edit.step(1, up: false)
    XCTAssertEqual(edit.items[1].servings, 0.5)
    XCTAssertEqual(edit.items[1].kcal, FoodRange(low: 50, high: 70))
    edit.step(0, up: false)
    edit.step(0, up: false)
    XCTAssertEqual(edit.items[0].servings, 1)
    XCTAssertEqual(edit.items[0].kcal, FoodRange(low: 100, high: 200))
    XCTAssertNil(edit.items[2].kcal, "an unknown range stays unknown, never 0")
    edit.step(2, up: true)
    XCTAssertEqual(edit.items[2].servings, 1.5, "no servings count is taken as 1")
    XCTAssertNil(edit.items[2].kcal)
    XCTAssertEqual(edit.items[2].proteinG, nil)
  }

  func testServingsNeverBelowHalf() throws {
    var edit = MealEdit(try match())
    for _ in 0..<5 { edit.step(1, up: false) }
    XCTAssertEqual(edit.items[1].servings, 0.5)
    XCTAssertEqual(edit.items[1].kcal, FoodRange(low: 50, high: 70))
    XCTAssertEqual(edit.items[1].proteinG, FoodRange(low: 3, high: 4))
    edit.step(1, up: true)
    XCTAssertEqual(edit.items[1].servings, 1)
    XCTAssertEqual(edit.items[1].kcal, FoodRange(low: 100, high: 140))
    edit.step(9, up: false)
    XCTAssertEqual(edit.items.count, 3, "a step outside the list changes nothing")
  }

  func testRemoveAndAddItem() throws {
    var edit = MealEdit(try match())
    edit.remove(2)
    XCTAssertEqual(edit.items.map(\.name), ["Rice", "Beans"])
    XCTAssertEqual(edit.totalKcal, FoodRange(low: 250, high: 440))
    XCTAssertEqual(edit.totalProteinG, FoodRange(low: 9, high: 14))

    edit.add(try item("Yogurt", kcal: 80, protein: 10))
    XCTAssertEqual(edit.items.map(\.name), ["Rice", "Beans", "Yogurt"])
    XCTAssertEqual(edit.items[2].servings, 1, "an added item joins at 1 serving")
    XCTAssertEqual(edit.totalKcal, FoodRange(low: 330, high: 600))

    edit.replace(0, with: try item("Pasta", kcal: 200, protein: 7))
    XCTAssertEqual(edit.items[0].name, "Pasta")
    XCTAssertEqual(edit.items[0].servings, 1.5, "a replacement keeps the servings counted")
    XCTAssertEqual(edit.items[0].kcal, FoodRange(low: 300, high: 600))
    XCTAssertEqual(edit.totalKcal, FoodRange(low: 480, high: 900))

    edit.remove(0)
    edit.remove(0)
    edit.remove(0)
    XCTAssertTrue(edit.items.isEmpty)
    XCTAssertNil(edit.totalKcal, "an empty meal has no total, not 0")

    let logged = LoggedMeal(
      id: UUID(), loggedAt: Date(timeIntervalSince1970: 0),
      items: [
        try item("Yogurt", kcal: 80, protein: 10)
      ])
    let copy = try JSONDecoder().decode(LoggedMeal.self, from: JSONEncoder().encode(logged))
    XCTAssertEqual(copy, logged)
    XCTAssertEqual(copy.status, .confirmed)
  }
}
