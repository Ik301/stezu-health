import XCTest

/// S-028: Settings shows the Hermes sync row, "--" before the first sync; Sync now sends the
/// scenario's synthetic Health samples to the fake POST /sync and the row shows the time and the
/// fake GET /sync/status count. `-uitest` never syncs on its own, so the row starts empty.
final class HermesSyncUITests: XCTestCase {
  @MainActor
  func testSyncNowUpdatesStatusRow() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "sync")

    // Open Settings: the row is there with "--" and a Sync now button.
    let gear = app.element("home.settings")
    XCTAssertTrue(gear.waitForExistence(timeout: 30), "no gear on Home")
    gear.tap()
    XCTAssertTrue(app.element("screen.settings.title").waitForExistence(timeout: 10))
    let row = app.element("settings.sync.status")
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no Hermes sync row")
    XCTAssertEqual(row.label, "--", "the row shows a sync before the first one")
    let syncNow = app.element("settings.sync.now")
    XCTAssertTrue(syncNow.exists, "no Sync now button")

    // One tap: the row shows when it ran and the fake server's sample count.
    syncNow.tap()
    let updated = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label CONTAINS '3 samples'"), object: row)
    XCTAssertEqual(
      XCTWaiter().wait(for: [updated], timeout: 15), .completed, "row is \(row.label)")
    XCTAssertFalse(row.label.hasPrefix("--"), "no sync time: \(row.label)")
    XCTAssertFalse(row.label.contains("waiting"), "batches still wait: \(row.label)")
    saveScreenshot("s028-sync-row", of: app)
  }
}
