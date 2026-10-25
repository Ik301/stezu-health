/// Every HealthKit call goes through this protocol (SPEC, Data sources). The app implements it
/// with HealthKit; tests and `-uitest` launches use FakeHealthStore. Stories add the reads and
/// writes they need here, to FakeHealthStore and to the app's HealthKitStore in the same card.
public protocol HealthStore: Sendable {
  /// False where Health data does not exist on the device.
  var isAvailable: Bool { get }

  /// Shows the one system sheet for every v1 read and write type. Success does not mean
  /// access was granted: HealthKit hides denied reads, so they look like absent data.
  func requestAuthorization() async throws
}

/// An in-memory HealthStore for tests and `-uitest` launches. It records what was asked of it.
public actor FakeHealthStore: HealthStore {
  public nonisolated let isAvailable: Bool
  /// How many times the permission sheet was requested.
  public private(set) var authorizationRequests = 0

  public init(isAvailable: Bool = true) {
    self.isAvailable = isAvailable
  }

  public func requestAuthorization() async throws {
    authorizationRequests += 1
  }
}
