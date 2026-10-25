import Foundation
import StezuCore
import XCTest

// Synthetic fixture: made-up hall, dishes and nutrition numbers.
private let menuFixture = """
  {
    "status": "available",
    "menu": {
      "hall": "example-hall",
      "date": "2026-01-15",
      "meals": [
        {
          "name": "Lunch",
          "items": [
            {
              "name": "Example Lentil Soup",
              "station": "Soups",
              "servingSize": "1 cup",
              "calories": 180,
              "proteinGrams": 11.5,
              "carbohydrateGrams": 27,
              "fatGrams": 2.5
            },
            { "name": "Example Garden Salad", "station": "Salad Bar", "calories": null }
          ]
        },
        { "name": "Dinner", "items": [] }
      ]
    }
  }
  """

private actor RecordingTransport: DiningMenuTransport {
  private(set) var requests: [DiningMenuRequest] = []
  private let response: DiningTransportResponse

  init(statusCode: Int, body: String) {
    response = DiningTransportResponse(statusCode: statusCode, body: Data(body.utf8))
  }

  func send(_ request: DiningMenuRequest) async throws -> DiningTransportResponse {
    requests.append(request)
    return response
  }
}

final class DiningMenuTests: XCTestCase {
  func testDecodesMenuFixture() throws {
    let result = try DiningMenuClient.decode(Data(menuFixture.utf8))
    let menu = try XCTUnwrap(result.menu)

    XCTAssertEqual(menu.hall, "example-hall")
    XCTAssertEqual(menu.date, "2026-01-15")
    XCTAssertEqual(menu.meals.map(\.name), ["Lunch", "Dinner"])

    let soup = menu.meals[0].items[0]
    XCTAssertEqual(soup.name, "Example Lentil Soup")
    XCTAssertEqual(soup.station, "Soups")
    XCTAssertEqual(soup.servingSize, "1 cup")
    XCTAssertEqual(soup.calories, 180)
    XCTAssertEqual(soup.proteinGrams, 11.5)
    XCTAssertEqual(soup.carbohydrateGrams, 27)
    XCTAssertEqual(soup.fatGrams, 2.5)

    // Missing or null nutrition stays nil, never 0.
    let salad = menu.meals[0].items[1]
    XCTAssertNil(salad.calories)
    XCTAssertNil(salad.proteinGrams)
    XCTAssertNil(salad.servingSize)

    // The models round-trip through JSON.
    let reencoded = try JSONDecoder().decode(DiningMenu.self, from: JSONEncoder().encode(menu))
    XCTAssertEqual(reencoded, menu)

    XCTAssertThrowsError(try DiningMenuClient.decode(Data("{\"menu\": 1}".utf8))) {
      XCTAssertEqual($0 as? DiningMenuError, .malformedBody)
    }
  }

  func testClientUsesInjectedTransport() async throws {
    let transport = RecordingTransport(statusCode: 200, body: menuFixture)
    let client = DiningMenuClient(transport: transport)

    let result = try await client.menu(hall: "example-hall", date: "2026-01-15")

    let requests = await transport.requests
    XCTAssertEqual(requests, [DiningMenuRequest(hall: "example-hall", date: "2026-01-15")])
    XCTAssertEqual(result.menu?.meals.first?.items.count, 2)

    let failing = DiningMenuClient(transport: RecordingTransport(statusCode: 500, body: ""))
    do {
      _ = try await failing.menu(hall: "example-hall", date: "2026-01-15")
      XCTFail("expected an error for status 500")
    } catch {
      XCTAssertEqual(error as? DiningMenuError, .unexpectedStatus(500))
    }
  }

  func testUnavailableMenuIsAbsentNotEmpty() async throws {
    let explicit = """
      {"status": "unavailable", "reason": "hall closed"}
      """
    let noItems = """
      {"status": "available",
       "menu": {"hall": "example-hall", "date": "2026-01-16", "meals": [{"name": "Lunch", "items": []}]}}
      """
    let cases: [(Int, String)] = [(200, explicit), (200, noItems), (404, "")]

    for (status, body) in cases {
      let client = DiningMenuClient(transport: RecordingTransport(statusCode: status, body: body))
      let result = try await client.menu(hall: "example-hall", date: "2026-01-16")

      XCTAssertNil(result.menu, "status \(status) should give no menu")
      guard case .unavailable(let reason) = result else {
        return XCTFail("status \(status) should be unavailable")
      }
      XCTAssertFalse(reason.isEmpty)
    }

    let closed = try DiningMenuClient.decode(Data(explicit.utf8))
    XCTAssertEqual(closed, .unavailable(reason: "hall closed"))
  }
}
