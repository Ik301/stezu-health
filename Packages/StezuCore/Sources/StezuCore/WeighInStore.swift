import Foundation

/// weigh-ins.json is the phone's source of truth (S-031, D-076). Id: a UUID, or an import's.
public struct StoredWeighIn: Codable, Sendable, Equatable {
  public let id: String
  public let measuredAt: Date
  public let pounds: Double
  /// Whether Health took it; nil until the write was tried.
  public var inHealth: Bool?
}

public struct WeighInLog: Codable, Sendable, Equatable {
  public var weighIns: [StoredWeighIn] = []
  public var migrated = false
  public init() {}
}

/// A `weigh_in` record's payload, with the field names of server/README.md.
public struct WeighInRecord: Codable, Sendable, Equatable {
  public let id, measuredAt: String
  public let pounds: Double
  public let inHealth: Bool?

  enum CodingKeys: String, CodingKey {
    case id, pounds
    case measuredAt = "measured_at"
    case inHealth = "in_health"
  }
}

extension SyncRecord {
  public static func weighIn(_ weighIn: StoredWeighIn, at date: Date, calendar: Calendar = .current)
    -> SyncRecord
  {
    let payload = WeighInRecord(
      id: weighIn.id, measuredAt: stamp(weighIn.measuredAt, calendar), pounds: weighIn.pounds,
      inHealth: weighIn.inHealth)
    return SyncRecord(
      kind: "weigh_in", id: weighIn.id, updatedAt: stamp(date, calendar), deleted: false,
      weighInPayload: payload)
  }

  public static func deletedWeighIn(_ id: String, at date: Date) -> SyncRecord {
    SyncRecord(kind: "weigh_in", id: id, updatedAt: stamp(date, .current), deleted: true)
  }
}

/// Every change is saved on the phone first, then made in Health, then queued through `sync`.
/// A failed Health call never undoes the phone's change.
public actor WeighInStore {
  public typealias Sync = @Sendable ([SyncRecord]) async -> Void
  public private(set) var log: WeighInLog
  private let save: @Sendable (WeighInLog) -> Void

  public init(
    log: WeighInLog = WeighInLog(), save: @escaping @Sendable (WeighInLog) -> Void = { _ in }
  ) {
    (self.log, self.save) = (log, save)
  }

  public func samples() -> [HealthSample] {
    log.weighIns.map {
      HealthSample(
        type: .bodyMass, date: $0.measuredAt, sourceName: "Stezu",
        sourceBundleID: WeeklyWeight.stezuBundleID, value: $0.pounds, id: $0.id)
    }
  }

  public func notInHealth() -> [StoredWeighIn] { log.weighIns.filter { $0.inHealth == false } }

  @discardableResult
  public func add(
    pounds: Double, at date: Date, id: String = UUID().uuidString, health: any HealthStore,
    sync: Sync
  ) async -> StoredWeighIn {
    var weighIn = StoredWeighIn(id: id, measuredAt: date, pounds: WeeklyWeight.tenths(pounds))
    log.weighIns.append(weighIn)
    save(log)
    weighIn.inHealth =
      (try? await health.saveBodyMass(pounds: weighIn.pounds, at: date, id: id)) != nil
    if let index = log.weighIns.firstIndex(where: { $0.id == id }) {
      log.weighIns[index] = weighIn
      save(log)
    }
    await sync([.weighIn(weighIn, at: Date())])
    return weighIn
  }

  /// The Day view's Delete: off the phone, then out of Health by id, then a tombstone.
  public func delete(at date: Date, health: any HealthStore, sync: Sync) async {
    let ids = log.weighIns.filter { $0.measuredAt == date }.map(\.id)
    guard !ids.isEmpty else { return }
    log.weighIns.removeAll { $0.measuredAt == date }
    save(log)
    for id in ids { try? await health.deleteBodyMass(id: id) }
    await sync(ids.map { .deletedWeighIn($0, at: Date()) })
  }

  /// Once per install: Stezu's body-mass samples in Health join the file, matched by id so
  /// nothing is doubled, and are queued. A read that throws tries again on the next read.
  public func migrate(from health: any HealthStore, sync: Sync) async {
    guard !log.migrated,
      let samples = try? await health.samples(of: .bodyMass, since: .distantPast), !log.migrated
    else { return }
    var known = Set(log.weighIns.map(\.id))
    var imported: [StoredWeighIn] = []
    for sample in samples where sample.sourceBundleID == WeeklyWeight.stezuBundleID {
      let id = sample.id ?? "health.\(Int(sample.date.timeIntervalSince1970 * 1000))"
      guard let pounds = sample.value, known.insert(id).inserted else { continue }
      imported.append(
        StoredWeighIn(id: id, measuredAt: sample.date, pounds: pounds, inHealth: true))
    }
    log.weighIns = (log.weighIns + imported).sorted { $0.measuredAt < $1.measuredAt }
    log.migrated = true
    save(log)
    if !imported.isEmpty { await sync(imported.map { .weighIn($0, at: Date()) }) }
  }
}

/// Health for the weight screens: Stezu's weigh-ins from the store, other apps' from Health (the
/// trend leaves those out, D-047). `migrates` stays false until Health has asked (S-020).
public struct WeighInHealth: HealthStore {
  let base: any HealthStore
  let store: WeighInStore
  let migrates: Bool
  let sync: WeighInStore.Sync

  public init(
    base: any HealthStore, store: WeighInStore, migrates: Bool, sync: @escaping WeighInStore.Sync
  ) {
    (self.base, self.store, self.migrates, self.sync) = (base, store, migrates, sync)
  }

  public func samples(of type: HealthType, since start: Date) async throws -> [HealthSample] {
    guard type == .bodyMass else { return try await base.samples(of: type, since: start) }
    if migrates { await store.migrate(from: base, sync: sync) }
    let others = ((try? await base.samples(of: type, since: start)) ?? [])
      .filter { $0.sourceBundleID != WeeklyWeight.stezuBundleID }
    let own = await store.samples().filter { $0.date >= start }
    return (others + own).sorted { $0.date < $1.date }
  }

  public var isAvailable: Bool { base.isAvailable }
  public func requestAuthorization() async throws { try await base.requestAuthorization() }
  public func latestSampleDate(of type: HealthType) async throws -> Date? {
    try await base.latestSampleDate(of: type)
  }
  public func saveStrengthWorkout(start: Date, end: Date, externalID: String) async throws {
    try await base.saveStrengthWorkout(start: start, end: end, externalID: externalID)
  }
  public func saveBodyMass(pounds: Double, at date: Date, id: String) async throws {
    try await base.saveBodyMass(pounds: pounds, at: date, id: id)
  }
  public func dailyValues(of type: HealthType, in span: DateInterval) async throws -> [Date: Double]
  {
    try await base.dailyValues(of: type, in: span)
  }
  public func sleepIntervals(since start: Date) async throws -> [SleepInterval] {
    try await base.sleepIntervals(since: start)
  }
  public func changes(of type: HealthType, after anchor: Data?, since start: Date, limit: Int)
    async throws -> HealthChanges
  { try await base.changes(of: type, after: anchor, since: start, limit: limit) }
  public func deleteBodyMass(at date: Date) async throws { try await base.deleteBodyMass(at: date) }
  public func deleteBodyMass(id: String) async throws { try await base.deleteBodyMass(id: id) }
  public func saveFood(_ entry: FoodEntry) async throws { try await base.saveFood(entry) }
  public func deleteFood(syncIdentifier: String) async throws {
    try await base.deleteFood(syncIdentifier: syncIdentifier)
  }
}
