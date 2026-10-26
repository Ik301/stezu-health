import Foundation
import StezuCore
import XCTest

/// Synthetic GET /search replies in the server's shape (server/stezu_server/search.py). Every
/// name, hall and number is made up.
final class FoodSearchClientTests: XCTestCase {
  static let reply = Data(
    #"""
    {"q": "rice", "date": "2026-01-05", "meal": "lunch", "groups": [
     {"source": "dining", "status": "ok", "results": [
      {"id": "01-L-1", "recipe_id": "1", "name": "Test Rice", "hall_id": "01", "hall": "North Hall",
       "meal": "Lunch", "station": "Grill", "serving": "4 oz", "kcal": 200.0, "protein_g": 4.0,
       "carbs_g": 40.0, "fat_g": 1.0, "halls": ["North Hall", "South Hall"], "score": 1.0},
      {"id": "02-L-9", "name": "Test Rice Pudding", "hall": "South Hall", "meal": "Lunch",
       "serving": "1/2 cup", "kcal": null, "protein_g": null, "halls": ["South Hall"], "score": 0.7}]},
     {"source": "open_food_facts", "status": "ok", "results": [
      {"gtin": "0000000000017", "name": "Test Rice Cakes", "brand": "Example Foods",
       "per_serving": {"label": "2 cakes (18 g)", "quantity": 18, "unit": "g", "kcal": 70,
        "protein_g": 1.4},
       "per_package": {"label": "100 g", "quantity": 100, "unit": "g", "kcal": 388, "protein_g": 8},
       "per_100": {"unit": "g", "kcal": 388, "protein_g": 8}}]},
     {"source": "usda_fdc", "status": "error", "error": "timed out", "results": []},
     {"source": "estimate", "status": "available", "results": []},
     {"source": "something_new", "status": "ok", "results": []}]}
    """#.utf8)

  static let estimateReply = Data(
    #"""
    {"q": "test burrito", "date": "2026-01-05", "meal": null, "groups": [
     {"source": "dining", "status": "ok", "results": []},
     {"source": "estimate", "status": "ok", "results": [
      {"name": "Test Burrito", "portion": "1 burrito", "rough": true, "spread_min": 0.4,
       "model_id": "test", "kcal": {"low": 600, "high": 1400},
       "protein_g": {"low": 30, "high": null}}]}]}
    """#.utf8)

  func group(_ groups: [FoodSearchGroup], _ source: FoodSearchSource) -> FoodSearchGroup? {
    groups.first { $0.source == source }
  }

  func testDecodesGroupedResults() async throws {
    let fake = FakeVMTransport(routes: ["GET /search": VMResponse(status: 200, body: Self.reply)])
    let results = try await FoodSearchClient(transport: fake).search(
      "rice", date: "2026-01-05", meal: .lunch)

    XCTAssertEqual(
      results.map(\.source), [.dining, .openFoodFacts, .usdaFdc, .estimate])
    let dining = try XCTUnwrap(group(results, .dining)).items
    XCTAssertEqual(dining.map(\.name), ["Test Rice", "Test Rice Pudding"])
    XCTAssertEqual(dining[0].hall, "North Hall")
    XCTAssertEqual(dining[0].halls, ["North Hall", "South Hall"])
    XCTAssertEqual(dining[0].serving, "4 oz")
    XCTAssertEqual(dining[0].servings, 1)
    XCTAssertEqual(dining[0].kcal, FoodRange(low: 150, high: 250))
    XCTAssertEqual(dining[0].proteinG, FoodRange(low: 3, high: 5))
    XCTAssertFalse(dining[0].isRough)
    XCTAssertNil(dining[1].kcal, "a missing value stays unknown, never 0")
    XCTAssertNil(dining[1].proteinG)

    let packaged = try XCTUnwrap(group(results, .openFoodFacts)).items
    XCTAssertEqual(packaged.first?.name, "Test Rice Cakes")
    XCTAssertEqual(packaged.first?.brand, "Example Foods")
    XCTAssertNil(packaged.first?.hall)
    XCTAssertEqual(packaged.first?.serving, "2 cakes (18 g)")
    XCTAssertEqual(packaged.first?.kcal, FoodRange(low: 52.5, high: 87.5))
    XCTAssertEqual(group(results, .usdaFdc)?.status, "error")
    XCTAssertEqual(group(results, .usdaFdc)?.items, [])
    XCTAssertEqual(group(results, .estimate)?.status, "available")

    let requests = await fake.sent
    let sent = try XCTUnwrap(requests.first)
    XCTAssertEqual(sent.route, "GET /search")
    XCTAssertEqual(sent.query, ["q": "rice", "date": "2026-01-05", "meal": "lunch"])
  }

  func testTextEstimateIsRough() async throws {
    let fake = FakeVMTransport(routes: [
      "GET /search": VMResponse(status: 200, body: Self.reply),
      "GET /search?estimate=true": VMResponse(status: 200, body: Self.estimateReply),
    ])
    let client = FoodSearchClient(transport: fake)
    let estimate = try await client.estimate("test burrito", date: "2026-01-05")
    let item = try XCTUnwrap(estimate)

    XCTAssertEqual(item.name, "Test Burrito")
    XCTAssertTrue(item.isRough)
    XCTAssertEqual(item.serving, "1 burrito")
    XCTAssertEqual(item.servings, 1)
    XCTAssertEqual(item.kcal, FoodRange(low: 600, high: 1400))
    XCTAssertNil(item.proteinG, "a range with a null end is unknown")
    let kcal = try XCTUnwrap(item.kcal)
    let mid = (kcal.low + kcal.high) / 2
    XCTAssertGreaterThan(
      (kcal.high - mid) / mid, FoodSearchClient.pickSpread, "rough is wider than a pick")

    let requests = await fake.sent
    let sent = try XCTUnwrap(requests.first)
    XCTAssertEqual(sent.query["estimate"], "true")
    XCTAssertEqual(sent.query["q"], "test burrito")

    let plain = try await client.search("test burrito", date: "2026-01-05", meal: nil)
    XCTAssertEqual(group(plain, .estimate)?.status, "available", "no estimate unless asked")
  }
}
