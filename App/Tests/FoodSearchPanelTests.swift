import StezuCore
import XCTest

@testable import StezuHealth

final class FoodSearchPanelTests: XCTestCase {
  @MainActor
  func testFixtureGroupsAndDetailLines() throws {
    let groups = try FoodSearchClient.decode(Data(UITestFixtures.searchReply.utf8))
    let listed = FoodSearchPanel.listed(groups)
    XCTAssertEqual(
      listed.map(\.title), ["Dining halls", "Packaged food", "Restaurants and generic (USDA)"],
      "the server's group order, the estimate left to its button")
    for section in listed {
      XCTAssertEqual(section.group.items.count, 1, section.title)
    }
    let details = listed.flatMap(\.group.results).map(\.detail)
    XCTAssertEqual(
      details, ["North Hall, South Hall · 4 oz", "Example Dairy · 500 g · 1 cup", "1 burrito"])

    let estimate = try FoodSearchClient.decode(Data(UITestFixtures.estimateReply.utf8))
    let rough = try XCTUnwrap(estimate.first?.results.first)
    XCTAssertTrue(rough.item.isRough)
    XCTAssertEqual(rough.detail, "1 bowl")
  }

  /// Synthetic: his own food comes back first under "Your foods", and every group keeps the
  /// server's order, even when a later group would sort ahead by name.
  @MainActor
  func testHistoryGroupIsListedFirstUnderYourFoods() throws {
    let reply = #"""
      {"q": "test oats", "groups": [
       {"source": "history", "title": "Your foods", "status": "ok", "results": [
        {"kind": "food", "id": "0000000000048", "gtin": "0000000000048", "name": "Test Oats",
         "brand": "Example Mill", "serving": "1 cup", "servings": 1,
         "kcal": {"low": 225, "high": 375}, "protein_g": {"low": 7.5, "high": 12.5},
         "log_count": 4, "last_logged_at": "2026-01-04T08:00:00-05:00", "score": 1.0}]},
       {"source": "dining", "status": "ok", "results": []},
       {"source": "open_food_facts", "status": "ok", "results": [
        {"gtin": "0000000000055", "name": "Test Oats", "brand": "Example Mill",
         "package_size": "1 kg", "per_serving": {"label": "100 g", "kcal": 380,
         "basis": "per_100"}}]},
       {"source": "usda_fdc", "status": "skipped", "results": []},
       {"source": "estimate", "status": "available", "results": []}]}
      """#
    let listed = FoodSearchPanel.listed(try FoodSearchClient.decode(Data(reply.utf8)))
    XCTAssertEqual(listed.map(\.title), ["Your foods", "Dining halls", "Packaged food"])
    XCTAssertEqual(listed.first?.group.results.map(\.detail), ["Example Mill · 1 cup"])
    XCTAssertEqual(listed.last?.group.results.map(\.detail), ["Example Mill · 1 kg"])
  }
}
