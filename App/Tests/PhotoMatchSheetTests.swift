import CryptoKit
import StezuCore
import UIKit
import XCTest

@testable import StezuHealth

final class PhotoMatchSheetTests: XCTestCase {
  func testMatcherSendsDownscaledPhotoWithItsHash() async throws {
    let environment = AppEnvironment.fakes(scenario: UITestFixtures.photoMatchScenario)
    let photo = await FixturePhotoSource.plateJPEG(side: 1600)
    let meal = try await environment.mealCaptures.save(photo: photo, at: Date())

    let state = await MealMatcher(environment: environment).match(meal)

    guard case .matched(let match) = state else { return XCTFail("not matched: \(state)") }
    XCTAssertEqual(match.items.count, 3)
    let transport = try XCTUnwrap(environment.vmTransport as? FakeVMTransport)
    let sent = await transport.sent
    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try XCTUnwrap(sent.first?.body)) as? [String: String])
    XCTAssertEqual(body["meal_id"], meal.id.uuidString.lowercased())
    let jpeg = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(body["image_base64"])))
    let hash = SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined()
    XCTAssertEqual(body["photo_sha256"], hash)
    let image = try XCTUnwrap(UIImage(data: jpeg))
    XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 1000)
  }

  @MainActor
  func testMissingRangeShowsDashesNeverZero() {
    XCTAssertEqual(FoodRange.text(nil, unit: "kcal"), "-- kcal")
    XCTAssertEqual(
      FoodRange.text(FoodRange(low: 99.6, high: 140.2), unit: "kcal"), "100–140 kcal")
  }

  /// S-050: meals have no names, so the toast names one by the time of day.
  func testToastNamesTheMealByTimeOfDay() {
    let at = { (hour: Int, minute: Int) in
      Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }
    XCTAssertEqual(FoodView.toast(at: at(10, 59), inHealth: true), "Breakfast logged, in Health")
    XCTAssertEqual(FoodView.toast(at: at(12, 30), inHealth: true), "Lunch logged, in Health")
    XCTAssertEqual(FoodView.toast(at: at(15, 59), inHealth: false), "Lunch logged, not in Health")
    XCTAssertEqual(FoodView.toast(at: at(16, 0), inHealth: nil), "Dinner logged")
  }
}
