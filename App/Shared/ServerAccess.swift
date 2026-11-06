import Foundation
import Security
import StezuCore

// Compiled into the app and the RestActivity extension, so the home-screen widgets reach the
// server the same way the app does (D-152).

/// The VM server: an address and a bearer token, typed once in Settings. The repo holds neither
/// (D-034).
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

  /// The address and token as saved in the Keychain: what the widget extension uses.
  static func fromKeychain() -> ServerSettings {
    ServerSettings(
      address: ServerKeychain.read(.address) ?? "", token: ServerKeychain.read(.token) ?? "")
  }
}

/// The server items in the Keychain (service com.ik301.stezuhealth.server), this device only.
/// Queries name no access group: the app writes into its default group, and the extension,
/// whose entitlements list that group (App/RestActivity.entitlements), finds the same items.
enum ServerKeychain {
  enum Account: String {
    case token, address
  }

  private static func query(_ account: Account) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.ik301.stezuhealth.server",
      kSecAttrAccount as String: account.rawValue,
    ]
  }

  static func read(_ account: Account) -> String? {
    var lookup = Self.query(account)
    lookup[kSecReturnData as String] = true
    var result: AnyObject?
    guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess else { return nil }
    return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
  }

  /// Replaces the item; an empty value only deletes it.
  static func write(_ value: String, for account: Account) throws {
    SecItemDelete(Self.query(account) as CFDictionary)
    guard !value.isEmpty else { return }
    var item = Self.query(account)
    item[kSecValueData as String] = Data(value.utf8)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
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
