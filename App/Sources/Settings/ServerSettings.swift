import Foundation
import Security
import StezuCore

/// The VM server: an address (kept in UserDefaults) and a bearer token (kept in the Keychain),
/// typed once in Settings. The repo holds neither (D-034).
struct ServerSettings: Sendable, Equatable {
  var address = ""
  var token = ""

  /// An http(s) URL with a host, or nil. An address typed without a scheme gets https.
  var baseURL: URL? {
    let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, let url = URL(string: text.contains("://") ? text : "https://" + text),
      ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false
    else { return nil }
    return url
  }

  var trimmedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }
  var isConfigured: Bool { baseURL != nil && !trimmedToken.isEmpty }
  /// Dots once a token is saved, "--" before.
  var maskedToken: String { trimmedToken.isEmpty ? "--" : String(repeating: "•", count: 8) }

  /// The live transport, or UnconfiguredVMTransport while the address or token is missing.
  func transport(session: URLSession = .shared) -> any VMTransport {
    guard let baseURL, isConfigured else { return UnconfiguredVMTransport() }
    return URLSessionVMTransport(baseURL: baseURL, token: trimmedToken, session: session)
  }
}

protocol ServerSettingsStore: Sendable {
  func load() -> ServerSettings
  func save(_ settings: ServerSettings) throws
}

/// The phone's store: the address in UserDefaults, the token in the Keychain (this device only).
struct DeviceServerSettingsStore: ServerSettingsStore {
  private static let addressKey = "server.address"
  private static var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.ik301.stezuhealth.server", kSecAttrAccount as String: "token",
    ]
  }

  func load() -> ServerSettings {
    var query = Self.query
    query[kSecReturnData as String] = true
    var result: AnyObject?
    let found = SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    let token = found ? (result as? Data).flatMap { String(data: $0, encoding: .utf8) } : nil
    return ServerSettings(
      address: UserDefaults.standard.string(forKey: Self.addressKey) ?? "", token: token ?? "")
  }

  func save(_ settings: ServerSettings) throws {
    UserDefaults.standard.set(settings.address, forKey: Self.addressKey)
    SecItemDelete(Self.query as CFDictionary)
    guard !settings.trimmedToken.isEmpty else { return }
    var item = Self.query
    item[kSecValueData as String] = Data(settings.trimmedToken.utf8)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
  }
}

/// Settings in memory, for `-uitest` launches and tests: empty on every launch.
final class MemoryServerSettingsStore: ServerSettingsStore, @unchecked Sendable {
  private let lock = NSLock()
  private var settings = ServerSettings()

  func load() -> ServerSettings { lock.withLock { settings } }
  func save(_ settings: ServerSettings) throws { lock.withLock { self.settings = settings } }
}

/// The answer to Test connection. Server features show the same `text`, so a missing server
/// reads "Set up the server in Settings", never a crash or a 0.
enum ServerConnection: Sendable, Equatable {
  case untested, connected, notConfigured, unreachable
  case failed(status: Int)

  var text: String {
    switch self {
    case .untested: "--"
    case .connected: "Connected"
    case .notConfigured: "Set up the server in Settings"
    case .unreachable: "Can't reach the server"
    case .failed(let status): "The server answered \(status)"
    }
  }

  /// GET /health; Connected only for 200 with `"status": "ok"`.
  static func check(_ transport: any VMTransport) async -> ServerConnection {
    struct Health: Decodable { var status: String }
    do {
      let response = try await transport.send(VMRequest(path: "/health"))
      let health = try? JSONDecoder().decode(Health.self, from: response.body)
      return response.status == 200 && health?.status == "ok"
        ? .connected : .failed(status: response.status)
    } catch VMTransportError.notConfigured {
      return .notConfigured
    } catch {
      return .unreachable
    }
  }
}

/// The live transport: the request path goes after the base URL's path, and every call carries
/// `Authorization: Bearer <token>`. Network failures become `unreachable`.
struct URLSessionVMTransport: VMTransport {
  let baseURL: URL
  let token: String
  var session: URLSession = .shared

  func send(_ request: VMRequest) async throws -> VMResponse {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw VMTransportError.notConfigured
    }
    let path = components.path
    components.path = (path.hasSuffix("/") ? String(path.dropLast()) : path) + request.path
    if !request.query.isEmpty {
      components.queryItems = request.query.sorted { $0.key < $1.key }
        .map { URLQueryItem(name: $0.key, value: $0.value) }
    }
    guard let url = components.url else { throw VMTransportError.notConfigured }
    var urlRequest = URLRequest(url: url, timeoutInterval: 30)
    urlRequest.httpMethod = request.method
    urlRequest.httpBody = request.body
    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    urlRequest.setValue(request.contentType, forHTTPHeaderField: "Content-Type")
    guard let reply = try? await session.data(for: urlRequest),
      let http = reply.1 as? HTTPURLResponse
    else { throw VMTransportError.unreachable("no HTTP reply from the server") }
    return VMResponse(status: http.statusCode, body: reply.0)
  }
}
