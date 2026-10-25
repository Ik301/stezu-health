import StezuCore
import XCTest

final class VersionTests: XCTestCase {
  func testVersionIsSet() {
    XCTAssertEqual(StezuCore.version, "0.1.0")
  }
}
