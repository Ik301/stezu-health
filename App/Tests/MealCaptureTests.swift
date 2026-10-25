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
}
