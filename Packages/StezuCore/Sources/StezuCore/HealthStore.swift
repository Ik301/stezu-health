import Foundation

/// Every HealthKit call goes through this protocol (SPEC, Data sources). The app implements it
/// with HealthKit; tests and `-uitest` launches use FakeHealthStore. Stories add the reads and
/// writes they need here, to FakeHealthStore and to the app's HealthKitStore in the same card.
public protocol HealthStore: Sendable {
  /// False where Health data does not exist on the device.
  var isAvailable: Bool { get }

  /// Shows the one system sheet for every v1 read and write type. Success does not mean
  /// access was granted: HealthKit hides denied reads, so they look like absent data.
  func requestAuthorization() async throws

  /// Samples of `type` dated from `start` on, oldest first. Denied reads return none.
  func samples(of type: HealthType, since start: Date) async throws -> [HealthSample]

  /// The newest sample's date, or nil when there is none (or the read is denied).
  func latestSampleDate(of type: HealthType) async throws -> Date?
}

/// An in-memory HealthStore for tests and `-uitest` launches. It records what was asked of it.
public actor FakeHealthStore: HealthStore {
  public nonisolated let isAvailable: Bool
  /// How many times the permission sheet was requested.
  public private(set) var authorizationRequests = 0
  /// Synthetic samples the reads return.
  public private(set) var storedSamples: [HealthSample]

  public init(isAvailable: Bool = true, samples: [HealthSample] = []) {
    self.isAvailable = isAvailable
    self.storedSamples = samples
  }

  public func requestAuthorization() async throws {
    authorizationRequests += 1
  }

  public func samples(of type: HealthType, since start: Date) async throws -> [HealthSample] {
    storedSamples.filter { $0.type == type && $0.date >= start }.sorted { $0.date < $1.date }
  }

  public func latestSampleDate(of type: HealthType) async throws -> Date? {
    storedSamples.filter { $0.type == type }.map(\.date).max()
  }
}
