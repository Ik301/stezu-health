import Foundation
import StezuCore
import XCTest

/// Synthetic POST /scan replies in the server/README.md shape. Every name and number is made up.
final class PhotoMatchClientTests: XCTestCase {
  static let reply = Data(
    #"""
    {"estimate_id": "e1", "meal_id": "m1", "photo_sha256": "ab", "date": "2026-01-05",
     "meal": "lunch", "mode": "dining", "model_id": "test", "candidates": 40, "rough": false,
     "complete": true, "cached": false,
     "items": [
      {"region_id": null, "item_id": "01-L-1", "name": "Test Rice", "hall": "North Hall",
       "halls": ["North Hall"], "serving": "4 oz", "servings": 1.5, "confidence": 0.9,
       "rough": false, "alternates": [], "kcal": {"low": 200, "high": 260},
       "protein_g": {"low": 4, "high": 5.2}},
      {"region_id": null, "item_id": "02-L-7", "name": "Test Beans", "hall": "South Hall",
       "halls": ["South Hall", "East Hall"], "serving": "1/2 cup", "servings": 1,
       "confidence": 0.7, "rough": false, "alternates": [],
       "kcal": {"low": 100, "high": 140}, "protein_g": {"low": 6, "high": 8.4}},
      {"region_id": null, "item_id": "unlisted", "name": "Test Cookie", "hall": null,
       "halls": [], "serving": null, "servings": 1, "confidence": 0.4,
       "alternates": [], "kcal": {"low": 120, "high": 280}, "protein_g": {"low": 1, "high": null}}
     ],
     "totals": {"kcal": {"low": 420, "high": 680}, "protein_g": {"low": 11, "high": null}}}
    """#.utf8)

  func testDecodesItemsAcrossHalls() async throws {
    let fake = FakeVMTransport(routes: ["POST /scan": VMResponse(status: 200, body: Self.reply)])
    let id = UUID()
    let match = try await PhotoMatchClient(transport: fake).scan(
      mealID: id, date: "2026-01-05", meal: .lunch, jpeg: Data([0xFF, 0xD8]), sha256: "ab")

    XCTAssertEqual(match.items.map(\.name), ["Test Rice", "Test Beans", "Test Cookie"])
    XCTAssertEqual(match.items.map(\.hall), ["North Hall", "South Hall", nil])
    XCTAssertEqual(match.items[1].halls, ["South Hall", "East Hall"])
    XCTAssertEqual(match.items[0].servings, 1.5)
    XCTAssertEqual(match.items[0].confidence, 0.9)
    XCTAssertEqual(match.items[0].kcal, FoodRange(low: 200, high: 260))
    XCTAssertEqual(match.items[1].proteinG, FoodRange(low: 6, high: 8.4))
    XCTAssertFalse(match.items[0].isRough)

    let requests = await fake.sent
    let sent = try XCTUnwrap(requests.first)
    XCTAssertEqual(sent.route, "POST /scan")
    XCTAssertEqual(sent.contentType, "application/json")
    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try XCTUnwrap(sent.body)) as? [String: String])
    XCTAssertEqual(body["meal_id"], id.uuidString.lowercased())
    XCTAssertEqual(body["meal"], "lunch")
    XCTAssertEqual(body["date"], "2026-01-05")
    XCTAssertEqual(body["mode"], "dining")
    XCTAssertEqual(body["photo_sha256"], "ab")
    XCTAssertEqual(body["image_base64"], Data([0xFF, 0xD8]).base64EncodedString())
  }

  func testUnlistedItemIsRoughWithWiderRange() throws {
    let match = try PhotoMatchClient.decode(Self.reply)
    let cookie = match.items[2]

    XCTAssertEqual(cookie.itemId, MatchedItem.unlistedID)
    XCTAssertTrue(cookie.isRough, "an unlisted item must be rough even without a rough flag")
    XCTAssertNil(cookie.hall)
    XCTAssertNil(cookie.proteinG, "a range with a null end is unknown, not zero")
    let width = try halfWidth(XCTUnwrap(cookie.kcal))
    XCTAssertGreaterThanOrEqual(width, 0.4)
    for listed in match.items.prefix(2) {
      XCTAssertLessThan(try halfWidth(XCTUnwrap(listed.kcal)), width)
    }
  }

  func testNonOKStatusThrows() async {
    let fake = FakeVMTransport(routes: ["POST /scan": VMResponse(status: 502)])
    do {
      _ = try await PhotoMatchClient(transport: fake).scan(
        mealID: UUID(), date: "d", meal: .dinner, jpeg: Data(), sha256: "")
      XCTFail("a 502 must throw")
    } catch {
      XCTAssertEqual(error as? PhotoMatchError, .unexpectedStatus(502))
    }
  }

  /// Half the width over the midpoint: 0.4 is the midpoint plus or minus 40%.
  private func halfWidth(_ range: FoodRange) -> Double {
    (range.high - range.low) / (range.high + range.low)
  }

  func testMealPeriodFollowsTimeOfDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
    let day = Date(timeIntervalSince1970: 0)
    let at = { (hour: Int, minute: Int) in
      MealPeriod.at(day.addingTimeInterval(Double(hour * 3600 + minute * 60)), calendar: calendar)
    }
    XCTAssertEqual(at(8, 0), .breakfast)
    XCTAssertEqual(at(10, 30), .lunch)
    XCTAssertEqual(at(15, 59), .lunch)
    XCTAssertEqual(at(18, 0), .dinner)
  }
}
