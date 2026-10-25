import Foundation
import StezuCore
import XCTest

final class VMTransportTests: XCTestCase {
  func testFakeAnswersByMethodAndPath() async throws {
    let body = Data(#"{"status":"ok"}"#.utf8)
    let fake = FakeVMTransport(routes: ["GET /health": VMResponse(status: 200, body: body)])

    let hit = try await fake.send(VMRequest(path: "/health"))
    let miss = try await fake.send(VMRequest(method: "POST", path: "/health"))

    XCTAssertEqual(hit, VMResponse(status: 200, body: body))
    XCTAssertEqual(miss.status, 404)
    let routes = await fake.sent.map(\.route)
    XCTAssertEqual(routes, ["GET /health", "POST /health"])
  }

  func testOfflineFakeThrowsUnreachable() async {
    let fake = FakeVMTransport(offline: true)
    do {
      _ = try await fake.send(VMRequest(path: "/menu"))
      XCTFail("an offline transport must throw")
    } catch {
      XCTAssertEqual(error as? VMTransportError, .unreachable("the fake transport is offline"))
    }
    await fake.setOffline(false)
    let response = try? await fake.send(VMRequest(path: "/menu"))
    XCTAssertEqual(response?.status, 404)
  }

  func testUnconfiguredTransportThrowsNotConfigured() async {
    do {
      _ = try await UnconfiguredVMTransport().send(VMRequest(path: "/menu"))
      XCTFail("an unconfigured transport must throw")
    } catch {
      XCTAssertEqual(error as? VMTransportError, .notConfigured)
    }
  }
}
