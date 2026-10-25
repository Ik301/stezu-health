import StezuCore
import XCTest

@testable import StezuHealth

final class AppEnvironmentTests: XCTestCase {
  func testUITestArgumentSelectsFakes() async {
    let environment = AppEnvironment.fromLaunch(arguments: [
      "StezuHealth", "-uitest", "-uitest-scenario", "example", "-uitest-offline",
    ])
    XCTAssertTrue(environment.isUITest)
    XCTAssertEqual(environment.storage, .memory)
    XCTAssertEqual(environment.scenario, "example")
    XCTAssertTrue(environment.healthStore is FakeHealthStore)
    XCTAssertTrue(environment.photoSource is FixturePhotoSource)
    let transport = environment.vmTransport as? FakeVMTransport
    XCTAssertNotNil(transport)
    let offline = await transport?.isOffline
    XCTAssertEqual(offline, true)
  }

  func testNoArgumentSelectsLiveServices() {
    let environment = AppEnvironment.fromLaunch(arguments: ["StezuHealth"])
    XCTAssertFalse(environment.isUITest)
    XCTAssertEqual(environment.storage, .disk)
    XCTAssertNil(environment.scenario)
    XCTAssertTrue(environment.healthStore is HealthKitStore)
    XCTAssertTrue(environment.vmTransport is UnconfiguredVMTransport)
    XCTAssertTrue(environment.photoSource is NoCameraPhotoSource)
  }

  func testPersistKeepsTheStoreInATemporaryFolder() {
    let environment = AppEnvironment.fromLaunch(arguments: [
      "StezuHealth", "-uitest", "-uitest-persist",
    ])
    guard case .temporary(let folder) = environment.storage else {
      return XCTFail("expected a temporary store, got \(environment.storage)")
    }
    XCTAssertEqual(folder.lastPathComponent, "stezu-uitest-store")
  }

  func testFixturePhotoIsAJPEG() async throws {
    let data = try await FixturePhotoSource().capturePhoto()
    XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8])
  }
}
