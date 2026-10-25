import StezuCore
import XCTest

final class FoodRangeTests: XCTestCase {
  func testMealTotalSumsLowsAndHighs() {
    let total = FoodRange.total([
      FoodRange(low: 200, high: 260), FoodRange(low: 100, high: 140),
      FoodRange(low: 120, high: 280),
    ])
    XCTAssertEqual(total, FoodRange(low: 420, high: 680))
    XCTAssertNil(FoodRange.total([]), "an empty meal has no total, not 0")
    XCTAssertNil(
      FoodRange.total([FoodRange(low: 1, high: 2), nil]), "an unknown item makes the total unknown")
  }

  func testHeldFakeRouteWaitsUntilCancelled() async {
    let fake = FakeVMTransport(held: ["POST /scan"])
    let task = Task { try await fake.send(VMRequest(method: "POST", path: "/scan")) }
    try? await Task.sleep(nanoseconds: 50_000_000)
    task.cancel()
    let result = await task.result
    XCTAssertThrowsError(try result.get())
  }
}
