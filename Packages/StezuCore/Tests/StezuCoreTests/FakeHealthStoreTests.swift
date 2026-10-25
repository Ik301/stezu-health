import StezuCore
import XCTest

final class FakeHealthStoreTests: XCTestCase {
  func testFakeRecordsAuthorizationRequests() async throws {
    let store = FakeHealthStore()
    XCTAssertTrue(store.isAvailable)
    let before = await store.authorizationRequests
    try await store.requestAuthorization()
    let after = await store.authorizationRequests
    XCTAssertEqual(before, 0)
    XCTAssertEqual(after, 1)
    XCTAssertFalse(FakeHealthStore(isAvailable: false).isAvailable)
  }
}
