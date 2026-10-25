import XCTest

/// S-012: one tap from Home into the camera, then one tap on the shutter saves the photo locally
/// and shows "Matching...".
final class FoodCameraUITests: XCTestCase {
  @MainActor
  func testFoodOpensCameraAndShutterSavesPhoto() {
    continueAfterFailure = false
    let app = UITestApp.launch()

    // Step 1: one tap on the Food card opens the camera with its controls.
    let card = app.element("home.card.food")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no food card on Home")
    card.tap()
    XCTAssertTrue(
      app.element("food.camera.preview").waitForExistence(timeout: 10), "no camera image")
    for id in ["nav.home", "food.mode.photo", "food.mode.barcode", "food.shutter", "food.history"] {
      XCTAssertTrue(app.element(id).waitForExistence(timeout: 10), "no \(id) on the camera")
    }
    let home = app.element("nav.home").frame
    let window = app.windows.firstMatch.frame
    XCTAssertLessThan(home.midX, window.midX, "Home is not on the left")
    XCTAssertLessThan(home.midY, window.midY, "Home is not at the top")
    XCTAssertEqual(app.element("food.mode.photo").value as? String, "on")
    XCTAssertEqual(app.element("food.mode.barcode").value as? String, "off")
    XCTAssertFalse(app.element("food.camera.denied").exists, "the fixture camera was denied")
    saveScreenshot("s012-camera", of: app)

    // Step 3: one tap on the shutter saves the photo and shows "Matching...".
    let shutter = app.element("food.shutter")
    expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: shutter)
    waitForExpectations(timeout: 10)
    shutter.tap()
    let matching = app.element("food.matching")
    XCTAssertTrue(matching.waitForExistence(timeout: 10), "no Matching... sheet")
    XCTAssertEqual(matching.label, "Matching...")
    XCTAssertTrue(app.element("food.captured.saved").exists, "the sheet does not confirm the save")
    saveScreenshot("s012-captured", of: app)
  }
}
