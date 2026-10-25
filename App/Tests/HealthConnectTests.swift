import Foundation
import StezuCore
import XCTest

@testable import StezuHealth

final class HealthConnectTests: XCTestCase {
  func testAsksOnlyOnce() async throws {
    let suite = "stezu-health-connect-test"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = FakeHealthStore()

    // Nothing is asked until Connect.
    let connection = HealthConnection(defaults: defaults)
    XCTAssertFalse(connection.isConnected)
    let before = await store.authorizationRequests
    XCTAssertEqual(before, 0)

    try await connection.connect(to: store)
    try await connection.connect(to: store)
    XCTAssertTrue(connection.isConnected)
    let afterTwoTaps = await store.authorizationRequests
    XCTAssertEqual(afterTwoTaps, 1)

    // A relaunch reads the saved flag and does not ask again.
    let relaunched = HealthConnection(defaults: defaults)
    XCTAssertTrue(relaunched.isConnected)
    try await relaunched.connect(to: store)
    let afterRelaunch = await store.authorizationRequests
    XCTAssertEqual(afterRelaunch, 1)
  }
}
