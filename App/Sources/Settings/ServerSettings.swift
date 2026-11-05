import Foundation
import StezuCore

protocol ServerSettingsStore: Sendable {
  func load() -> ServerSettings
  func save(_ settings: ServerSettings) throws
}

/// The phone's store: the address in UserDefaults and the Keychain, the token in the Keychain
/// (this device only). The Keychain copies are what the widget extension reads (D-152).
struct DeviceServerSettingsStore: ServerSettingsStore {
  private static let addressKey = "server.address"

  func load() -> ServerSettings {
    ServerSettings(
      address: UserDefaults.standard.string(forKey: Self.addressKey) ?? "",
      token: ServerKeychain.read(.token) ?? "")
  }

  /// Only a failed token write throws. The address copy is for the widget, so the app works
  /// even when that write fails.
  func save(_ settings: ServerSettings) throws {
    UserDefaults.standard.set(settings.address, forKey: Self.addressKey)
    try? ServerKeychain.write(settings.address, for: .address)
    try ServerKeychain.write(settings.trimmedToken, for: .token)
  }

  /// At launch: an install from before the widget has its address in UserDefaults only, so copy
  /// it to the Keychain once and the widget works without saving Settings again.
  func copyAddressToKeychainIfMissing() {
    guard ServerKeychain.read(.address) == nil,
      let address = UserDefaults.standard.string(forKey: Self.addressKey), !address.isEmpty
    else { return }
    try? ServerKeychain.write(address, for: .address)
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
