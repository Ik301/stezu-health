import Foundation
import StezuCore
import XCTest

@testable import StezuHealth

/// Answers every request with 200 `{"status": "ok"}` and keeps the last request, so the live
/// transport is exercised without a network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var lastRequest: URLRequest?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lastRequest = request
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
    else { return }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(#"{"status": "ok", "version": "0.1.0"}"#.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

final class ServerSettingsTests: XCTestCase {
  func testLiveTransportSendsBearerToken() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    // Synthetic address and token (D-034); the stub answers, nothing leaves the simulator.
    let settings = ServerSettings(address: "vm.example:8443/api/", token: " synthetic-token ")
    let transport = settings.transport(session: session)
    XCTAssertTrue(transport is URLSessionVMTransport)

    let response = try await transport.send(VMRequest(path: "/menu", query: ["date": "2026-01-05"]))
    XCTAssertEqual(response.status, 200)
    let sent = try XCTUnwrap(StubURLProtocol.lastRequest)
    XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-token")
    XCTAssertEqual(sent.httpMethod, "GET")
    XCTAssertEqual(sent.url?.absoluteString, "https://vm.example:8443/api/menu?date=2026-01-05")

    let connection = await ServerConnection.check(transport)
    XCTAssertEqual(connection, .connected)
    XCTAssertEqual(connection.text, "Connected")
  }

  func testNoServerIsNotConfigured() async throws {
    let cases = [
      ServerSettings(),
      ServerSettings(address: "https://vm.example", token: ""),
      ServerSettings(address: "", token: "synthetic-token"),
      ServerSettings(address: "ftp://vm.example", token: "synthetic-token"),
    ]
    for settings in cases {
      XCTAssertFalse(settings.isConfigured, "\(settings.address)")
      let transport = settings.transport()
      XCTAssertTrue(transport is UnconfiguredVMTransport)
      do {
        _ = try await transport.send(VMRequest(path: "/health"))
        XCTFail("an unconfigured transport answered")
      } catch {
        XCTAssertEqual(error as? VMTransportError, .notConfigured)
      }
      let connection = await ServerConnection.check(transport)
      XCTAssertEqual(connection, .notConfigured)
      XCTAssertEqual(connection.text, "Set up the server in Settings")
    }
    XCTAssertEqual(ServerSettings().maskedToken, "--")

    // A -uitest environment starts with nothing saved, and saving does not replace the fake.
    var environment = AppEnvironment.fakes()
    XCTAssertEqual(environment.serverSettings.load(), ServerSettings())
    let saved = ServerSettings(address: "https://vm.example", token: "synthetic-token")
    try environment.serverSettings.save(saved)
    XCTAssertEqual(environment.serverSettings.load(), saved)
    XCTAssertEqual(saved.maskedToken, "••••••••")
    environment.useServer(saved)
    XCTAssertTrue(environment.vmTransport is FakeVMTransport)
  }
}
