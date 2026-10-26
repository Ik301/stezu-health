import Foundation

/// One call to the VM server, relative to the base URL set in the app's Settings.
public struct VMRequest: Sendable, Equatable {
  public var method: String
  /// A path such as "/menu"; the live transport appends it to the base URL.
  public var path: String
  public var query: [String: String]
  public var body: Data?
  public var contentType: String?

  public init(
    method: String = "GET", path: String, query: [String: String] = [:], body: Data? = nil,
    contentType: String? = nil
  ) {
    self.method = method
    self.path = path
    self.query = query
    self.body = body
    self.contentType = contentType
  }

  /// "GET /menu": the key FakeVMTransport answers by.
  public var route: String { "\(method) \(path)" }
}

/// A raw reply: an HTTP status code and the body.
public struct VMResponse: Sendable, Equatable {
  public var status: Int
  public var body: Data

  public init(status: Int, body: Data = Data()) {
    self.status = status
    self.body = body
  }
}

public enum VMTransportError: Error, Sendable, Equatable {
  /// No base URL or token has been set in Settings yet.
  case notConfigured
  /// The server could not be reached. Callers keep the work queued and retry later.
  case unreachable(String)
}

/// Moves a request to the VM server and back. The app's live transport adds the base URL and the
/// bearer token from Settings; tests and `-uitest` launches use FakeVMTransport. Core imports no
/// networking, and the repo holds no server address or token.
public protocol VMTransport: Sendable {
  func send(_ request: VMRequest) async throws -> VMResponse
}

/// The app's transport until a server is set in Settings: every call is `notConfigured`.
public struct UnconfiguredVMTransport: VMTransport {
  public init() {}

  public func send(_ request: VMRequest) async throws -> VMResponse {
    throw VMTransportError.notConfigured
  }
}

/// Canned responses keyed by route ("POST /scan"). Unknown routes answer 404. It records every
/// request, and while offline it throws `unreachable`, as a phone without a connection would.
/// Held routes never answer, like a server still working: the call waits until its task ends.
public actor FakeVMTransport: VMTransport {
  private var routes: [String: VMResponse]
  private let held: Set<String>
  public private(set) var sent: [VMRequest] = []
  public private(set) var isOffline: Bool

  public init(routes: [String: VMResponse] = [:], offline: Bool = false, held: Set<String> = []) {
    self.routes = routes
    self.isOffline = offline
    self.held = held
  }

  public func setResponse(_ response: VMResponse, for route: String) {
    routes[route] = response
  }

  public func setOffline(_ offline: Bool) {
    isOffline = offline
  }

  public func send(_ request: VMRequest) async throws -> VMResponse {
    sent.append(request)
    if isOffline {
      throw VMTransportError.unreachable("the fake transport is offline")
    }
    while held.contains(request.route) {
      try await Task.sleep(nanoseconds: 1_000_000_000)
    }
    // A key may add one query pair ("GET /search?estimate=true"); it wins when it matches.
    let narrower = request.query.compactMap { routes["\(request.route)?\($0.key)=\($0.value)"] }
    return narrower.first ?? routes[request.route] ?? VMResponse(status: 404)
  }
}
