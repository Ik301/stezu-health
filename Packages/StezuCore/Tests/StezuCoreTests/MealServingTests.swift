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

  /// S-050: one formatter writes every food range: an en dash, thousands commas, whole numbers,
  /// "--" when unknown, never a hyphen or a midpoint.
  func testRangeFormatterUsesEnDashAndGrouping() {
    XCTAssertEqual(
      FoodRange.text(FoodRange(low: 1240, high: 1480), unit: "kcal"), "1,240\u{2013}1,480 kcal")
    XCTAssertEqual(FoodRange.text(FoodRange(low: 92.4, high: 117.6), unit: "g"), "92\u{2013}118 g")
    XCTAssertEqual(FoodRange.text(FoodRange(low: 999.6, high: 12_345)), "1,000\u{2013}12,345")
    XCTAssertEqual(FoodRange.text(FoodRange(low: 0, high: 5)), "0\u{2013}5")
    XCTAssertEqual(FoodRange.text(nil, unit: "kcal"), "-- kcal", "absent is --, not 0")
    XCTAssertEqual(FoodRange.text(nil), "--")
    XCTAssertFalse(FoodRange.text(FoodRange(low: 200, high: 260)).contains("-"), "a hyphen")
    XCTAssertEqual(
      MealQueue.todayText(loggedKcal: FoodRange(low: 1080, high: 1440), pending: 1),
      "1,080\u{2013}1,440 kcal, +1 pending")
  }
  /// D-158: once the user steps a menu item's servings, its range is the menu value times
  /// servings plus or minus 10% (15 points more for estimated menu values), never wider than it
  /// was. Unlisted and rough items keep their ranges. Made-up halls and dishes.
  private func menuMatch() throws -> PhotoMatch {
    try PhotoMatchClient.decode(
      Data(
        #"""
        {"meal_id": "m", "items": [
         {"item_id": "A-1", "name": "Glazed Trout", "hall": "Hall A", "halls": ["Hall A"],
          "serving": "5 oz", "servings": 1, "confidence": 0.72, "rough": false, "estimated": false,
          "kcal": {"low": 212, "high": 388}, "protein_g": {"low": 15.6, "high": 28.4}},
         {"item_id": "unlisted", "name": "Cucumber", "hall": null, "halls": [], "servings": 1,
          "rough": true, "kcal": {"low": 12, "high": 28}, "protein_g": {"low": 0.5, "high": 1.5}},
         {"item_id": "L-1", "name": "Grill Burger", "hall": "Hall C", "halls": ["Hall C"],
          "servings": 1, "rough": false, "estimated": true,
          "kcal": {"low": 300, "high": 700}, "protein_g": {"low": 15, "high": 35}},
         {"item_id": "A-2", "name": "Jasmine Rice", "hall": "Hall A", "servings": 2,
          "kcal": {"low": 228, "high": 252}, "protein_g": {"low": 3.8, "high": 4.2}}]}
        """#.utf8))
  }

  private func assertRange(
    _ range: FoodRange?, _ low: Double, _ high: Double, _ message: String = "",
    line: UInt = #line
  ) {
    XCTAssertEqual(range?.low ?? .nan, low, accuracy: 0.001, message, line: line)
    XCTAssertEqual(range?.high ?? .nan, high, accuracy: 0.001, message, line: line)
  }

  func testSteppedMenuItemNarrowsToMenuValueTimesServings() throws {
    var edit = MealEdit(try menuMatch())
    XCTAssertEqual(edit.items[2].estimated, true)
    edit.step(0, up: true)
    XCTAssertEqual(edit.items[0].servings, 1.5)
    assertRange(edit.items[0].kcal, 405, 495, "300 kcal x 1.5, plus or minus 10%")
    assertRange(edit.items[0].proteinG, 29.7, 36.3)
    edit.step(0, up: false)
    assertRange(edit.items[0].kcal, 270, 330, "back at 1 serving it stays narrow")
    edit.step(1, up: true)
    assertRange(edit.items[1].kcal, 18, 42, "an unlisted estimate keeps its width")
    edit.step(2, up: false)
    edit.step(2, up: true)
    assertRange(edit.items[2].kcal, 375, 625, "an estimated menu value: plus or minus 25%")
    edit.step(3, up: true)
    assertRange(edit.items[3].kcal, 285, 315, "already narrower than 10%: never widened")
    assertRange(edit.totalKcal, 948, 1312)
  }

  func testUnsteppedAndReplacedItemsKeepTheServerRange() throws {
    var edit = MealEdit(try menuMatch())
    XCTAssertEqual(edit.items[0].kcal, FoodRange(low: 212, high: 388))
    edit.replace(0, with: try menuMatch().items[3])
    XCTAssertEqual(edit.items[0].kcal, FoodRange(low: 114, high: 126), "a pick is not a portion")
    let logged = LoggedMeal(id: UUID(), loggedAt: Date(timeIntervalSince1970: 0), items: edit.items)
    let data = try JSONEncoder().encode(logged)
    XCTAssertEqual(try JSONDecoder().decode(LoggedMeal.self, from: data), logged)
  }
}
