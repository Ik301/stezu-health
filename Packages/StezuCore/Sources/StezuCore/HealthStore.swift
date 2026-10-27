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
  /// Deletes the strength workout Stezu wrote with this external id, so a continued session
  /// can be written again (S-036). Other apps' workouts are never touched.
  func deleteStrengthWorkout(externalID: String) async throws

  /// Writes one body-mass sample, Stezu as its source, tagged with the weigh-in `id` (S-031).
  func saveBodyMass(pounds: Double, at date: Date, id: String) async throws

  /// Per-day statistics keyed by day start, merged across apps by Health: totals for steps,
  /// means for discrete types such as resting heart rate. A day without data has no key.
  func dailyValues(of type: HealthType, in interval: DateInterval) async throws -> [Date: Double]

  /// sleepAnalysis stages that end from `start` on.
  func sleepIntervals(since start: Date) async throws -> [SleepInterval]
  /// Up to `limit` changes after `anchor` (opaque), or from `start` on without one (S-028).
  func changes(of type: HealthType, after anchor: Data?, since start: Date, limit: Int)
    async throws -> HealthChanges
  /// Deletes Stezu's own body-mass samples dated `date` (S-025); other apps' are untouched.
  func deleteBodyMass(at date: Date) async throws
  /// Deletes Stezu's body-mass sample whose weigh-in id or Health UUID is `id` (S-031).
  func deleteBodyMass(id: String) async throws

  /// Writes one logged meal as a food correlation (S-018). An entry with the same sync
  /// identifier replaces the one in Health. Throws when the write is denied or fails.
  func saveFood(_ entry: FoodEntry) async throws
  /// Removes the meal's food entry and the samples inside it (Undo).
  func deleteFood(syncIdentifier: String) async throws
}

extension HealthStore {
  public func saveBodyMass(pounds: Double, at date: Date) async throws {
    try await saveBodyMass(pounds: pounds, at: date, id: UUID().uuidString)
  }
}

/// One page of an anchored Health read (S-028).
public typealias HealthChanges = (samples: [SyncSample], deleted: [SyncDeletion], anchor: Data?)

public enum HealthChange: Sendable {
  case added(SyncSample)
  case deleted(SyncDeletion)
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
    isAvailable: Bool = true, samples: [HealthSample] = [], sleep: [SleepInterval] = [],
    changes: [HealthType: [HealthChange]] = [:]
  ) {
    self.isAvailable = isAvailable
    self.storedSamples = samples
    self.storedSleep = sleep
    self.changeLog = changes
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

  public func deleteStrengthWorkout(externalID: String) async throws {
    if failsWrites { throw FakeHealthStoreError.writeFailed }
    savedWorkouts.removeAll { $0.externalID == externalID }
  }

  public func saveBodyMass(pounds: Double, at date: Date, id: String) async throws {
    if failsWrites { throw FakeHealthStoreError.writeFailed }
    storedSamples.append(
      HealthSample(
        type: .bodyMass, date: date, sourceName: "Stezu",
        sourceBundleID: WeeklyWeight.stezuBundleID, value: pounds, id: id))
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

  /// Changes per type, oldest first; the anchor counts those read and `since` is ignored.
  private let changeLog: [HealthType: [HealthChange]]

  public func changes(of type: HealthType, after anchor: Data?, since start: Date, limit: Int)
    async throws -> HealthChanges
  {
    let read = anchor.flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
    let page = (changeLog[type] ?? []).dropFirst(read).prefix(limit)
    var (samples, deleted): ([SyncSample], [SyncDeletion]) = ([], [])
    for change in page {
      switch change {
      case .added(let sample): samples.append(sample)
      case .deleted(let deletion): deleted.append(deletion)
      }
    }
    return (samples, deleted, Data(String(read + page.count).utf8))
  }

  public func deleteBodyMass(at date: Date) async throws {
    if failsWrites { throw FakeHealthStoreError.writeFailed }
    storedSamples.removeAll {
      $0.type == .bodyMass && $0.date == date && $0.sourceBundleID == WeeklyWeight.stezuBundleID
    }
  }

  public func deleteBodyMass(id: String) async throws {
    if failsWrites { throw FakeHealthStoreError.writeFailed }
    storedSamples.removeAll { $0.type == .bodyMass && $0.id == id }
  }

  /// Food entries written, one per sync identifier.
  public private(set) var savedFoods: [FoodEntry] = []

  public func saveFood(_ entry: FoodEntry) async throws {
    if failsWrites { throw FakeHealthStoreError.writeFailed }
    savedFoods.removeAll { $0.syncIdentifier == entry.syncIdentifier }
    savedFoods.append(entry)
  }

  public func deleteFood(syncIdentifier: String) async throws {
    savedFoods.removeAll { $0.syncIdentifier == syncIdentifier }
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
