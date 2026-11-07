import StezuCore
import XCTest

@testable import StezuHealth

final class MealCaptureTests: XCTestCase {
  func testShutterSavesPhotoBeforeAnyNetworkCall() async throws {
    let environment = AppEnvironment.fakes(offline: true)
    let fixed = Date(timeIntervalSince1970: 1_000_000)
    var capture = MealCapture(environment: environment)
    capture.now = { fixed }

    let meal = try await capture.shutter()

    let saved = await environment.mealCaptures.all()
    XCTAssertEqual(saved, [meal])
    XCTAssertEqual(meal.capturedAt, fixed)
    let photo = await environment.mealCaptures.photo(for: meal.id)
    XCTAssertEqual(
      photo.map { Array($0.prefix(2)) }, [0xFF, 0xD8], "the saved photo is not a JPEG")
    let transport = try XCTUnwrap(environment.vmTransport as? FakeVMTransport)
    let sent = await transport.sent
    XCTAssertTrue(sent.isEmpty, "the shutter sent \(sent.map(\.route)) before matching")
  }

  func testDiskStoreKeepsMealsAcrossInstances() async throws {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("meal-capture-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = MealCaptureStore(storage: .temporary(folder))
    let meal = try await first.save(photo: Data([0xFF, 0xD8, 0x01]), at: Date())

    let second = MealCaptureStore(storage: .temporary(folder))
    let all = await second.all()
    XCTAssertEqual(all, [meal])
    let photo = await second.photo(for: meal.id)
    XCTAssertEqual(photo, Data([0xFF, 0xD8, 0x01]))
  }

  /// S-063: a text estimate (rough, no hall or brand) logged by search is read back.
  func testSearchEstimateRoundTripsThroughLog() async throws {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("meal-log-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let groups = try FoodSearchClient.decode(Data(UITestFixtures.estimateReply.utf8))
    let item = try XCTUnwrap(groups.first { $0.source == .estimate }?.items.first)
    XCTAssertTrue(item.isRough)
    XCTAssertNil(item.hall)
    XCTAssertNil(item.brand)
    var meal = LoggedMeal(id: UUID(), loggedAt: Date(), items: [item])
    meal.inHealth = true
    try await MealCaptureStore(storage: .temporary(folder)).log(meal)

    let store = MealCaptureStore(storage: .temporary(folder))
    let logged = await store.logged()
    XCTAssertEqual(logged, [meal])
    let today = await store.days().first
    XCTAssertEqual(today?.meals.map(\.id), [meal.id], "the estimate is not in History")
  }

  /// S-063: the VM's meals reach the meal store once, not Health and not the sync queue; a
  /// queued delete keeps its meal deleted, and offline nothing changes.
  func testPullSavesServerMealsOnceAndNotToHealth() async throws {
    let offline = AppEnvironment.fakes(scenario: "food-server-history", offline: true)
    let pulledOffline = await offline.pullMeals()
    XCTAssertFalse(pulledOffline)
    let none = await offline.mealCaptures.logged()
    XCTAssertEqual(none, [])

    let environment = AppEnvironment.fakes(scenario: "food-server-history")
    let pulled = await environment.pullMeals()
    XCTAssertTrue(pulled)
    let logged = await environment.mealCaptures.logged()
    XCTAssertEqual(logged.map(\.items.first?.name), ["Lentil Soup", "Green Salad"])
    let again = await environment.pullMeals()
    XCTAssertFalse(again, "a second read saved the meals again")
    let health = try XCTUnwrap(environment.healthStore as? FakeHealthStore)
    let foods = await health.savedFoods
    XCTAssertEqual(foods, [], "server meals were written to Health")
    let queued = await environment.healthSync.state.pending
    XCTAssertEqual(queued, [], "server meals were queued for sync")

    let deleting = AppEnvironment.fakes(scenario: "food-server-history")
    let soup = try XCTUnwrap(logged.first?.id)
    await deleting.healthSync.enqueue([.deletedMeal(soup, at: Date())])
    _ = await deleting.pullMeals()
    let kept = await deleting.mealCaptures.logged()
    XCTAssertEqual(kept.map(\.items.first?.name), ["Green Salad"], "the deleted meal came back")
  }
}
