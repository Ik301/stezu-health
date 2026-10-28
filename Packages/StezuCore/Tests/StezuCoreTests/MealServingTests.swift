import StezuCore
import XCTest

/// S-043: the match sheet's - and + change an item's servings in half steps, never below 0.5,
/// and its ranges and the sheet's totals follow. All values are made up (D-034).
final class MealServingTests: XCTestCase {
  private func match() throws -> PhotoMatch {
    try PhotoMatchClient.decode(
      Data(
        #"""
        {"meal_id": "m", "items": [
         {"item_id": "a", "name": "Grain Bowl", "serving": "1 bowl", "servings": 1,
          "kcal": {"low": 200, "high": 280}, "protein_g": {"low": 10, "high": 14}},
         {"item_id": "b", "name": "Greens", "serving": "1 cup", "servings": 1,
          "kcal": {"low": 40, "high": 60}, "protein_g": {"low": 2, "high": 4}}]}
        """#.utf8))
  }

  func testHalfStepServingsScaleRanges() throws {
    var edit = MealEdit(try match())
    XCTAssertEqual(edit.totalKcal, FoodRange(low: 240, high: 340))
    edit.step(1, up: true)
    XCTAssertEqual(edit.items[1].servings, 1.5)
    XCTAssertEqual(edit.items[1].kcal, FoodRange(low: 60, high: 90))
    XCTAssertEqual(edit.items[1].proteinG, FoodRange(low: 3, high: 6))
    XCTAssertEqual(edit.totalKcal, FoodRange(low: 260, high: 370), "the total follows the item")
    XCTAssertEqual(edit.totalProteinG, FoodRange(low: 13, high: 20))
    edit.step(0, up: true)
    edit.step(0, up: true)
    XCTAssertEqual(edit.items[0].servings, 2)
    XCTAssertEqual(edit.items[0].kcal, FoodRange(low: 400, high: 560))
    edit.step(1, up: false)
    XCTAssertEqual(edit.items[1].servings, 1)
    XCTAssertEqual(edit.items[1].kcal, FoodRange(low: 40, high: 60), "back to what was matched")
  }

  func testServingsNeverBelowHalf() throws {
    var edit = MealEdit(try match())
    edit.step(0, up: false)
    XCTAssertEqual(edit.items[0].servings, 0.5)
    XCTAssertEqual(edit.items[0].kcal, FoodRange(low: 100, high: 140))
    edit.step(0, up: false)
    edit.step(0, up: false)
    XCTAssertEqual(edit.items[0].servings, 0.5, "servings stop at one half")
    XCTAssertEqual(edit.items[0].kcal, FoodRange(low: 100, high: 140))
    XCTAssertEqual(edit.items.count, 2, "stepping down never removes the item")
    XCTAssertEqual(edit.totalKcal, FoodRange(low: 140, high: 200))
  }
}
