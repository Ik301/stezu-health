import Foundation
import XCTest

@testable import StezuCore

final class MealQueueTests: XCTestCase {
  private let reply = #"""
    {"meal_id": "m", "items": [{"item_id": "01-L-1", "name": "Herb Rice", "hall": "North Hall",
      "servings": 1, "kcal": {"low": 200, "high": 260}, "protein_g": {"low": 4, "high": 6}}]}
    """#

  private func meal(_ minutes: Double) -> QueuedMeal {
    QueuedMeal(id: UUID(), capturedAt: Date(timeIntervalSince1970: 1_800_000_000 + minutes * 60))
  }

  func testOfflineMealStaysPending() async throws {
    var queue = MealQueue([meal(0)])
    let transport = FakeVMTransport(offline: true)

    let matched = await queue.retry { _ in
      try await PhotoMatchClient(transport: transport).scan(
        mealID: UUID(), date: "2027-01-15", meal: .lunch, jpeg: Data([1]), sha256: "00")
    }

    XCTAssertEqual(matched, [])
    XCTAssertEqual(queue.meals.count, 1, "an offline meal left the queue")
    XCTAssertEqual(queue.pending.count, 1)
    XCTAssertNil(queue.meals[0].match)
  }

  func testQueueRetriesInOrder() async throws {
    let first = meal(0)
    let second = meal(10)
    let third = meal(20)
    var queue = MealQueue([third, first, second])
    let match = try PhotoMatchClient.decode(Data(reply.utf8))
    var order: [UUID] = []

    // The second meal's scan fails with a server error: it stays pending, the third still goes.
    let matched = await queue.retry { meal in
      order.append(meal.id)
      if meal.id == second.id { throw PhotoMatchError.unexpectedStatus(500) }
      return match
    }

    XCTAssertEqual(order, [first.id, second.id, third.id])
    XCTAssertEqual(matched, [first.id, third.id])
    XCTAssertEqual(queue.pending.map(\.id), [second.id])
    XCTAssertEqual(queue.meals.map(\.id), [first.id, second.id, third.id], "a meal was removed")

    // Offline: the round stops at the first meal and nothing is removed.
    order = []
    let none = await queue.retry { meal in
      order.append(meal.id)
      throw VMTransportError.unreachable("offline")
    }
    XCTAssertEqual(none, [])
    XCTAssertEqual(order, [second.id])
    XCTAssertEqual(queue.meals.count, 3)

    // Back online: only the pending meal is sent again.
    order = []
    _ = await queue.retry { meal in
      order.append(meal.id)
      return match
    }
    XCTAssertEqual(order, [second.id])
    XCTAssertTrue(queue.pending.isEmpty)
  }

  func testPendingNeverCountsAsZero() {
    let today = meal(0)
    let queue = MealQueue([today, meal(-2 * 24 * 60)])
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    let pending = queue.pendingCount(on: today.capturedAt, calendar: calendar)

    XCTAssertEqual(pending, 1)
    let text = MealQueue.todayText(loggedKcal: nil, pending: pending)
    XCTAssertEqual(text, "-- kcal, +1 pending")
    XCTAssertFalse(text.contains("0 kcal"))
    XCTAssertEqual(MealQueue.todayText(loggedKcal: nil, pending: 0), "-- kcal")
    XCTAssertEqual(
      MealQueue.todayText(loggedKcal: FoodRange(low: 400, high: 520), pending: 2),
      "400-520 kcal, +2 pending")
  }
}
