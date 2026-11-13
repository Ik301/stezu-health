import Foundation
import XCTest

@testable import StezuCore

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

  /// The creatine case, synthetic: one product in two tubs, his own entry first (D-158).
  static let packagedReply = Data(
    #"""
    {"q": "test creatine", "groups": [
     {"source": "history", "title": "Your foods", "status": "ok", "results": [
      {"kind": "food", "id": "0000000000062", "gtin": "0000000000062", "name": "Test Creatine",
       "brand": "Example Labs", "hall": null, "halls": null, "serving": "1 scoop (5 g)",
       "servings": 1, "rough": false, "kcal": null, "protein_g": null, "log_count": 9,
       "last_logged_at": "2026-01-04T08:00:00-05:00", "score": 1.0}]},
     {"source": "dining", "status": "ok", "results": []},
     {"source": "open_food_facts", "status": "ok", "results": [
      {"gtin": "0000000000079", "name": "Test Creatine Powder", "brand": "Example Labs",
       "package_size": "600 g", "per_serving": null, "per_100": null},
      {"gtin": "0000000000086", "name": "Test Creatine Powder", "brand": "Example Labs",
       "package_size": "300g", "per_serving": {"label": "100 g", "quantity": 100, "unit": "g",
       "kcal": 10, "protein_g": 0, "basis": "per_100"}},
      {"gtin": "0000000000093", "name": "Test Creatine Caps", "brand": null,
       "package_size": "120 g", "per_serving": {"label": "120 g", "kcal": 0}},
      {"gtin": "0000000000109", "name": "Test Creatine Chews", "brand": "Example Labs",
       "package_size": "  ", "per_serving": {"label": "100 g", "kcal": 300, "basis": "per_100"}}]},
     {"source": "usda_fdc", "status": "ok", "results": [
      {"fdc_id": 7, "name": "Test creatine drink", "brand": null, "package_size": "1.32 lb (600 g)",
       "per_serving": {"label": "1 bottle", "kcal": 50, "basis": "measure"}}]},
     {"source": "estimate", "status": "available", "results": []}]}
    """#.utf8)

  func packaged() throws -> [FoodSearchResult] {
    let groups = try FoodSearchClient.decode(Self.packagedReply)
    return try XCTUnwrap(group(groups, .openFoodFacts)).results
  }

  func testDetailShowsBrandAndPackageSize() throws {
    let rows = try packaged()
    XCTAssertEqual(rows[0].packageSize, "600 g")
    XCTAssertEqual(rows[0].detail, "Example Labs · 600 g")
    XCTAssertTrue(rows[1].servingIsPer100)
    XCTAssertEqual(rows[1].item.serving, "100 g", "the logged serving stays 100 g")
    XCTAssertEqual(rows[1].detail, "Example Labs · 300g", "no 100 g next to the package")
    XCTAssertNotEqual(rows[0].detail, rows[1].detail, "the two tubs read differently")
    let usda = try XCTUnwrap(group(try FoodSearchClient.decode(Self.packagedReply), .usdaFdc))
    XCTAssertEqual(
      usda.results.first?.detail, "1.32 lb (600 g) · 1 bottle", "a named serving stays")
  }

  func testDetailShowsPackageSizeOnly() throws {
    let caps = try packaged()[2]
    XCTAssertNil(caps.item.brand)
    XCTAssertEqual(caps.detail, "120 g", "a serving equal to the package shows once")
    let bare = FoodSearchResult(
      item: Self.item(brand: nil, serving: nil), packageSize: "250 ml", servingIsPer100: false)
    XCTAssertEqual(bare.detail, "250 ml")
  }

  func testDetailWithoutBrandOrPackageSizeKeepsTheOldLine() throws {
    let chews = try packaged()[3]
    XCTAssertNil(chews.packageSize, "a blank package size is absent")
    XCTAssertEqual(chews.detail, "Example Labs · 100 g")
    XCTAssertEqual(FoodSearchResult(item: Self.item(brand: nil, serving: "1 cup")).detail, "1 cup")
    XCTAssertEqual(FoodSearchResult(item: Self.item(brand: nil, serving: nil)).detail, "--")
  }

  func testOlderReplyWithoutNewFieldsDecodes() throws {
    let groups = try FoodSearchClient.decode(Self.reply)
    let cakes = try XCTUnwrap(group(groups, .openFoodFacts)?.results.first)
    XCTAssertNil(cakes.packageSize)
    XCTAssertFalse(cakes.servingIsPer100)
    XCTAssertEqual(cakes.detail, "Example Foods · 2 cakes (18 g)")
    XCTAssertNil(group(groups, .dining)?.title)
    XCTAssertNil(group(groups, .history), "an older server sends no history group")
  }

  func testGroupOrderIsKeptWithHistoryFirst() throws {
    let groups = try FoodSearchClient.decode(Self.packagedReply)
    XCTAssertEqual(
      groups.map(\.source), [.history, .dining, .openFoodFacts, .usdaFdc, .estimate])
    XCTAssertEqual(
      groups.filter(\.isListed).map(\.source), [.history, .dining, .openFoodFacts, .usdaFdc])
    let own = try XCTUnwrap(groups.first)
    XCTAssertEqual(own.title, "Your foods")
    XCTAssertEqual(own.items.map(\.name), ["Test Creatine"])
    XCTAssertEqual(own.items.first?.itemId, "0000000000062")
    XCTAssertEqual(own.results.first?.detail, "Example Labs · 1 scoop (5 g)")
    XCTAssertEqual(
      try packaged().map(\.item.itemId),
      ["0000000000079", "0000000000086", "0000000000093", "0000000000109"],
      "the server's relevance order, not kcal-first or by name")

    let empty = FoodSearchGroup(source: .history, title: "Your foods", status: "ok", results: [])
    XCTAssertFalse(empty.isListed, "no own foods match: no empty heading")
    XCTAssertTrue(FoodSearchGroup(source: .history, status: "error", results: []).isListed)
    XCTAssertTrue(FoodSearchGroup(source: .dining, status: "ok", results: []).isListed)
  }

  static func item(brand: String?, serving: String?) -> MatchedItem {
    MatchedItem(
      itemId: "1", name: "Test Food", hall: nil, halls: nil, brand: brand, serving: serving,
      servings: 1, confidence: nil, rough: nil, kcal: nil, proteinG: nil)
  }
}
