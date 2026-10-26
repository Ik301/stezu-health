import StezuCore
import XCTest

@testable import StezuHealth

final class MealLogStoreTests: XCTestCase {
  func testLoggedMealIsKeptAsConfirmedAndUndoRemovesIt() async throws {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("meal-log-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = MealCaptureStore(storage: .temporary(folder))
    let items = try PhotoMatchClient.decode(Data(UITestFixtures.scanReply.utf8)).items
    var edit = MealEdit(PhotoMatch(mealId: "m", items: items))
    edit.step(0, up: true)
    let meal = LoggedMeal(id: UUID(), loggedAt: Date(), items: edit.items)
    try await store.log(meal)

    let relaunched = await MealCaptureStore(storage: .temporary(folder)).logged()
    XCTAssertEqual(relaunched, [meal])
    XCTAssertEqual(relaunched.first?.status, .confirmed)
    XCTAssertEqual(relaunched.first?.items.first?.servings, 2)
    let queue = await store.queue()
    XCTAssertTrue(queue.meals.isEmpty, "a logged file is not a captured meal")

    await store.unlog(meal.id)
    let afterUndo = await store.logged()
    XCTAssertTrue(afterUndo.isEmpty)
  }
}
