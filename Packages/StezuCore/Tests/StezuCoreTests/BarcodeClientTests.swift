import Foundation
import StezuCore
import XCTest

/// Synthetic GET /barcode/{gtin} replies in the server's shape (server/README.md). Every name,
/// code and number is made up.
final class BarcodeClientTests: XCTestCase {
  static let found = Data(
    #"""
    {"status": "found", "source": "open_food_facts", "gtin": "0000000000031",
     "name": "Test Oat Bar", "brand": "Example Foods",
     "per_serving": {"label": "1 bar (40 g)", "quantity": 40, "unit": "g", "kcal": 160,
      "protein_g": 4},
     "per_package": {"label": "240 g", "quantity": 240, "unit": "g", "kcal": 960, "protein_g": 24},
     "per_100": {"unit": "g", "kcal": 400, "protein_g": 10}, "cached": false}
    """#.utf8)

  func testDecodesProduct() async throws {
    let fake = FakeVMTransport(routes: [
      "GET /barcode/0000000000031": VMResponse(status: 200, body: Self.found)
    ])
    let result = try await BarcodeClient(transport: fake).lookup("0000000000031")

    guard case .found(let item) = result else { return XCTFail("not found: \(result)") }
    XCTAssertEqual(item.itemId, "0000000000031")
    XCTAssertEqual(item.name, "Test Oat Bar")
    XCTAssertEqual(item.brand, "Example Foods")
    XCTAssertEqual(item.serving, "1 bar (40 g)")
    XCTAssertEqual(item.servings, 1)
    XCTAssertEqual(item.kcal, FoodRange(low: 120, high: 200))
    XCTAssertEqual(item.proteinG, FoodRange(low: 3, high: 5))
    XCTAssertFalse(item.isRough)
    let sent = await fake.sent
    XCTAssertEqual(sent.map(\.route), ["GET /barcode/0000000000031"])
  }

  func testUnknownCodeIsNotFoundNotEmpty() async throws {
    let reply = Data(#"{"status": "not_found", "gtin": "0000000000024"}"#.utf8)
    let fake = FakeVMTransport(routes: [
      "GET /barcode/0000000000024": VMResponse(status: 200, body: reply)
    ])
    let client = BarcodeClient(transport: fake)

    let result = try await client.lookup("0000000000024")
    XCTAssertEqual(result, .notFound(gtin: "0000000000024"))

    // A product with no per-serving values stays unknown ("--"), never 0 kcal.
    let bare = Data(#"{"status": "found", "gtin": "0000000000048", "name": "Test Tea"}"#.utf8)
    guard case .found(let item) = try BarcodeClient.decode(bare) else {
      return XCTFail("a named product is found")
    }
    XCTAssertNil(item.kcal)
    XCTAssertNil(item.proteinG)

    // A server error is an error, not "Not found"; only 8 to 14 digits are looked up.
    await fake.setResponse(VMResponse(status: 502), for: "GET /barcode/0000000000055")
    do {
      _ = try await client.lookup("0000000000055")
      XCTFail("a 502 must throw")
    } catch {
      XCTAssertEqual(error as? PhotoMatchError, .unexpectedStatus(502))
    }
    XCTAssertTrue(BarcodeClient.isGTIN("00000017"))
    XCTAssertFalse(BarcodeClient.isGTIN("1234567"))
    XCTAssertFalse(BarcodeClient.isGTIN("https://example.com"))
  }
}
