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

  /// Writes one traditional strength training workout with no energy samples. A workout with
  /// the same `externalID` already in Health is not written again, so a retry is safe.
  func saveStrengthWorkout(start: Date, end: Date, externalID: String) async throws

  /// Writes one body-mass sample. Health records Stezu as its source.
  func saveBodyMass(pounds: Double, at date: Date) async throws

  /// Per-day statistics keyed by day start, merged across apps by Health: totals for steps,
  /// means for discrete types such as resting heart rate. A day without data has no key.
  func dailyValues(of type: HealthType, in interval: DateInterval) async throws -> [Date: Double]

  /// sleepAnalysis stages that end from `start` on.
  func sleepIntervals(since start: Date) async throws -> [SleepInterval]
}

/// An in-memory HealthStore for tests and `-uitest` launches. It records what was asked of it.
public actor FakeHealthStore: HealthStore {
  public nonisolated let isAvailable: Bool
  /// How many times the permission sheet was requested.
  public private(set) var authorizationRequests = 0
  /// Synthetic samples the reads return.
  public private(set) var storedSamples: [HealthSample]

  public private(set) var storedSleep: [SleepInterval]

  public init(
    isAvailable: Bool = true, samples: [HealthSample] = [], sleep: [SleepInterval] = []
  ) {
    self.isAvailable = isAvailable
    self.storedSamples = samples
    self.storedSleep = sleep
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

  /// Strength workouts written, one per external id.
  public private(set) var savedWorkouts: [SavedWorkout] = []
  /// When true, every write throws, as a denied or failed HealthKit write does.
  public private(set) var failsWrites = false

  public func setFailsWrites(_ fails: Bool) {
    failsWrites = fails
  }

  public func saveStrengthWorkout(start: Date, end: Date, externalID: String) async throws {
    if failsWrites { throw FakeHealthStoreError.writeFailed }
    guard !savedWorkouts.contains(where: { $0.externalID == externalID }) else { return }
    savedWorkouts.append(SavedWorkout(start: start, end: end, externalID: externalID))
  }

  public func saveBodyMass(pounds: Double, at date: Date) async throws {
    if failsWrites { throw FakeHealthStoreError.writeFailed }
    storedSamples.append(
      HealthSample(
        type: .bodyMass, date: date, sourceName: "Stezu",
        sourceBundleID: WeeklyWeight.stezuBundleID, value: pounds))
  }

  /// Per day of the current calendar; unlike Health it keeps overlap between apps.
  public func dailyValues(of type: HealthType, in interval: DateInterval) async throws
    -> [Date: Double]
  {
    let inside = storedSamples.filter { $0.type == type && interval.contains($0.date) }
    return Dictionary(grouping: inside) { Calendar.current.startOfDay(for: $0.date) }
      .mapValues { day in
        let sum = day.compactMap(\.value).reduce(0, +)
        return type == .stepCount ? sum : sum / Double(day.count)
      }
  }

  public func sleepIntervals(since start: Date) async throws -> [SleepInterval] {
    storedSleep.filter { $0.end >= start }.sorted { $0.start < $1.start }
  }
}

/// A workout FakeHealthStore was asked to write.
public struct SavedWorkout: Sendable, Equatable {
  public let start: Date
  public let end: Date
  public let externalID: String

  public init(start: Date, end: Date, externalID: String) {
    self.start = start
    self.end = end
    self.externalID = externalID
  }
}

public enum FakeHealthStoreError: Error {
  case writeFailed
}
