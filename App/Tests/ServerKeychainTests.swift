import Foundation
import XCTest

@testable import StezuHealth

/// D-152: the app saves the server address and token where the widget extension reads them.
/// Synthetic values only; the test deletes what it wrote.
final class ServerKeychainTests: XCTestCase {
  func testSaveWritesTokenAndAddressForTheWidget() throws {
    let store = DeviceServerSettingsStore()
    defer {
      try? store.save(ServerSettings())
      UserDefaults.standard.removeObject(forKey: "server.address")
    }

    try store.save(ServerSettings(address: "https://vm.example", token: " synthetic-token "))

    XCTAssertEqual(ServerKeychain.read(.token), "synthetic-token")
    XCTAssertEqual(ServerKeychain.read(.address), "https://vm.example")
    XCTAssertEqual(
      ServerSettings.fromKeychain(),
      ServerSettings(address: "https://vm.example", token: "synthetic-token"))
    XCTAssertEqual(store.load().trimmedToken, "synthetic-token")

    // An install from before the widget has the address in UserDefaults only.
    try ServerKeychain.write("", for: .address)
    XCTAssertNil(ServerKeychain.read(.address))
    store.copyAddressToKeychainIfMissing()
    XCTAssertEqual(ServerKeychain.read(.address), "https://vm.example")

    try store.save(ServerSettings())
    XCTAssertNil(ServerKeychain.read(.token))
    XCTAssertNil(ServerKeychain.read(.address))
  }
}
