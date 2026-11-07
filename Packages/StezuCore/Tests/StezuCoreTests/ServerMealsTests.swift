import Foundation
import XCTest

@testable import StezuCore

/// S-063 (D-156): Food reads the VM's meals and keeps the ones the phone lacks. The phone's copy
/// wins, and a meal whose delete is still queued stays deleted. Every meal is made up (D-034).
final class ServerMealsTests: XCTestCase {
  private let id = UUID(uuidString: "5A1C7E3D-0000-4000-8000-000000000063")!

  /// One GET /records page as the server sends it: a rough text estimate (source "estimate",
  /// no halls), and a hall dish from yesterday.
  private func serverPage() throws -> [SyncRecord] {
    let body = #"""
      {"records": [
       {"kind": "meal", "id": "\#(id.uuidString)", "updated_at": "2026-03-11T15:00:30.000Z",
        "payload": {"id": "\#(id.uuidString)", "eaten_at": "2026-03-11T10:00:29-05:00",
         "day": "2026-03-11", "status": "confirmed", "edited": false, "in_health": true,
         "items": [{"item_id": "Latte", "source": "estimate", "name": "Latte", "rough": true,
          "serving": "1 cup", "servings": 1, "kcal": {"low": 110, "high": 260},
          "protein_g": {"low": 5, "high": 12}}]}},
       {"kind": "meal", "id": "6B2D8F4E-0000-4000-8000-000000000063",
        "updated_at": "2026-03-10T18:00:00.000Z",
        "payload": {"id": "6B2D8F4E-0000-4000-8000-000000000063",
         "eaten_at": "2026-03-10T18:00:00Z", "day": "2026-03-10", "status": "confirmed",
         "edited": false, "in_health": false,
         "items": [{"item_id": "01-L-9", "source": "North Hall", "halls": ["North Hall"],
          "name": "Lentil Soup", "rough": false, "servings": 1.5, "confidence": 0.8,
          "kcal": {"low": 180, "high": 240}, "protein_g": {"low": 9, "high": 13}}]}}],
       "next": null}
      """#
    return try JSONDecoder().decode(Restore.Page.self, from: Data(body.utf8)).records
      .compactMap(\.record)
  }

  func testServerOnlyMealComesBackWithItemsAndRanges() throws {
    let meals = Restore.newMeals(try serverPage(), local: [])

    XCTAssertEqual(meals.count, 2)
    let latte = try XCTUnwrap(meals.first { $0.id == id })
    XCTAssertEqual(latte.loggedAt, Date(timeIntervalSince1970: 1_773_241_229))
    XCTAssertEqual(latte.inHealth, true)
    let item = try XCTUnwrap(latte.items.first)
    XCTAssertEqual(item.name, "Latte")
    XCTAssertTrue(item.isRough)
    XCTAssertNil(item.hall, "an estimate is from no hall")
    XCTAssertNil(item.brand, "\"estimate\" is not a brand")
    XCTAssertEqual(item.kcal, FoodRange(low: 110, high: 260))
    XCTAssertEqual(item.proteinG, FoodRange(low: 5, high: 12))
    let soup = try XCTUnwrap(meals.first { $0.id != id })
    XCTAssertEqual(soup.items.first?.hall, "North Hall")
    XCTAssertEqual(soup.items.first?.servings, 1.5)
    XCTAssertEqual(soup.inHealth, false)
    XCTAssertEqual(FoodRange.text(FoodEntry(meal: soup).kcal), "180–240")
  }

  func testLocalCopyWinsAndLocalOnlyStays() throws {
    let records = try serverPage()
    let item = MatchedItem(
      itemId: "Latte", name: "Latte, edited", hall: nil, halls: nil, brand: nil, serving: nil,
      servings: 2, confidence: nil, rough: true, kcal: FoodRange(low: 220, high: 520),
      proteinG: FoodRange(low: 10, high: 24))
    let edited = LoggedMeal(id: id, loggedAt: Date(), items: [item])
    let localOnly = LoggedMeal(id: UUID(), loggedAt: Date(), items: [item])

    let meals = Restore.newMeals(records, local: [edited, localOnly])

    XCTAssertEqual(meals.map(\.items.first?.name), ["Lentil Soup"], "the phone's latte is replaced")
    XCTAssertFalse(meals.contains { $0.id == localOnly.id })
    XCTAssertEqual(
      Restore.newMeals(records, local: [edited, localOnly] + meals), [],
      "a second read brings nothing new")
    let twice = Restore.newMeals(records + records, local: [])
    XCTAssertEqual(twice.count, 2, "a meal listed twice is kept once")
  }

  private func batch(_ records: [SyncRecord]) -> SyncBatch {
    SyncBatch(deviceID: "d", batchID: "\(UUID())", samples: [], deleted: [], records: records)
  }

  func testPendingDeleteKeepsMealDeleted() throws {
    let records = try serverPage()
    var state = SyncState()
    let meal = Restore.newMeals(records, local: []).first { $0.id == id }!
    state.pending = [
      batch([.meal(meal, edited: false, at: Date())]),
      batch([.deletedMeal(id, at: Date())]),
    ]
    XCTAssertEqual(state.mealsBeingDeleted, [id])

    let meals = Restore.newMeals(records, local: [], deleting: state.mealsBeingDeleted)
    XCTAssertEqual(meals.map(\.items.first?.name), ["Lentil Soup"], "the deleted latte came back")

    state.pending.append(
      batch([.meal(meal, edited: true, at: Date())]))
    XCTAssertEqual(state.mealsBeingDeleted, [], "a later save of the meal is not a delete")
    state.pending = []
    XCTAssertEqual(state.mealsBeingDeleted, [], "an empty queue deletes nothing")
  }
}
