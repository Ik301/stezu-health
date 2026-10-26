import StezuCore
import XCTest

@testable import StezuHealth

final class MealQueueStoreTests: XCTestCase {
  func testOfflineMealIsPendingThenMatchedAndKeptAcrossRelaunch() async throws {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("meal-queue-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    var environment = AppEnvironment.fakes(
      scenario: UITestFixtures.photoMatchScenario, offline: true)
    environment.mealCaptures = MealCaptureStore(storage: .temporary(folder))
    let photo = await FixturePhotoSource.plateJPEG(side: 400)
    let meal = try await environment.mealCaptures.save(photo: photo, at: Date())

    let offline = await MealMatcher(environment: environment).match(meal)
    XCTAssertEqual(offline, .pending)
    let waiting = await environment.mealCaptures.queue()
    XCTAssertEqual(waiting.pending.map(\.id), [meal.id])

    let transport = try XCTUnwrap(environment.vmTransport as? FakeVMTransport)
    await transport.setOffline(false)
    let matched = await MealMatcher(environment: environment).retryQueue()
    XCTAssertEqual(matched?.id, meal.id)
    XCTAssertEqual(matched?.match?.items.count, 3)

    let relaunched = await MealCaptureStore(storage: .temporary(folder)).queue()
    XCTAssertEqual(relaunched.meals.map(\.id), [meal.id], "the meal left the store")
    XCTAssertTrue(relaunched.pending.isEmpty)
  }
}
