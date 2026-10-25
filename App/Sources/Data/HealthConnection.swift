import Foundation
import StezuCore

/// Whether Health has asked (S-020). Data asks once, on the first Connect tap, never at launch.
/// The live app keeps the flag in UserDefaults; `-uitest` keeps it in memory for the launch.
final class HealthConnection: @unchecked Sendable {
  private let defaults: UserDefaults?
  private let lock = NSLock()
  private var asked = false

  init(defaults: UserDefaults?) { self.defaults = defaults }

  var isConnected: Bool { lock.withLock { defaults?.bool(forKey: "health.connected") ?? asked } }

  /// Shows the one system sheet unless it has been shown. A throw leaves Connect to try again.
  func connect(to store: any HealthStore) async throws {
    guard !isConnected else { return }
    try await store.requestAuthorization()
    lock.withLock {
      asked = true
      defaults?.set(true, forKey: "health.connected")
    }
  }
}
