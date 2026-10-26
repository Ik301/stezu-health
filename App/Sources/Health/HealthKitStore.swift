import HealthKit
import StezuCore

/// The live HealthStore over HealthKit. Every HealthKit call in the app goes through here; the
/// stories add their reads and writes. Types follow D-033 and Research 10, section 5.
final class HealthKitStore: HealthStore, @unchecked Sendable {
  private let store = HKHealthStore()

  var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

  /// v1 writes: weigh-ins, meal energy and protein (inside a food correlation), strength workouts.
  static var shareTypes: Set<HKSampleType> {
    [
      HKQuantityType(.bodyMass), HKQuantityType(.dietaryEnergyConsumed),
      HKQuantityType(.dietaryProtein), HKObjectType.workoutType(),
    ]
  }

  /// v1 reads for the Data area. HRV, sleep and the strap's oxygen, breathing and temperature
  /// are context only.
  static var readTypes: Set<HKObjectType> {
    [
      HKQuantityType(.oxygenSaturation), HKQuantityType(.respiratoryRate),
      HKQuantityType(.bodyTemperature), HKQuantityType(.appleSleepingWristTemperature),
      HKQuantityType(.bodyMass), HKQuantityType(.stepCount), HKQuantityType(.heartRate),
      HKQuantityType(.heartRateVariabilitySDNN), HKQuantityType(.restingHeartRate),
      HKQuantityType(.dietaryEnergyConsumed), HKQuantityType(.dietaryProtein),
      HKCategoryType(.sleepAnalysis), HKObjectType.workoutType(),
    ]
  }

  func requestAuthorization() async throws {
    try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
  }

  func samples(of type: HealthType, since start: Date) async throws -> [HealthSample] {
    let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
    return try await query(type, predicate: predicate, limit: HKObjectQueryNoLimit, newest: false)
  }

  func latestSampleDate(of type: HealthType) async throws -> Date? {
    try await query(type, predicate: nil, limit: 1, newest: true).first?.date
  }

  /// Built with HKWorkoutBuilder, no energy samples. Skips the write when a workout with this
  /// external id is already in Health (a retry). Throws when the write is denied or fails.
  func saveStrengthWorkout(start: Date, end: Date, externalID: String) async throws {
    if store.authorizationStatus(for: HKObjectType.workoutType()) == .notDetermined {
      try await requestAuthorization()
    }
    let existing = HKSampleQueryDescriptor(
      predicates: [
        .workout(
          HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [externalID]))
      ], sortDescriptors: [], limit: 1)
    if let found = try? await existing.result(for: store), !found.isEmpty { return }

    let configuration = HKWorkoutConfiguration()
    configuration.activityType = .traditionalStrengthTraining
    let builder = HKWorkoutBuilder(
      healthStore: store, configuration: configuration, device: .local())
    try await builder.beginCollection(at: start)
    try await builder.addMetadata([HKMetadataKeyExternalUUID: externalID])
    try await builder.endCollection(at: end)
    guard try await builder.finishWorkout() != nil else { throw HKError(.errorInvalidArgument) }
  }

  func saveBodyMass(pounds: Double, at date: Date) async throws {
    let quantity = HKQuantity(unit: .pound(), doubleValue: pounds)
    try await store.save(
      HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: quantity, start: date, end: date))
  }

  func dailyValues(of type: HealthType, in interval: DateInterval) async throws -> [Date: Double] {
    guard let quantityType = type.sampleType as? HKQuantityType else { return [:] }
    let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
    return try await withCheckedThrowingContinuation { continuation in
      let query = HKStatisticsCollectionQuery(
        quantityType: quantityType, quantitySamplePredicate: predicate,
        options: type == .stepCount ? .cumulativeSum : .discreteAverage,
        anchorDate: interval.start, intervalComponents: DateComponents(day: 1))
      query.initialResultsHandler = { _, results, error in
        guard let results, let unit = type.unit else {
          return continuation.resume(throwing: error ?? CancellationError())
        }
        let days = results.statistics().reduce(into: [Date: Double]()) { days, day in
          let value = day.sumQuantity() ?? day.averageQuantity()
          days[day.startDate] = value?.doubleValue(for: unit)
        }
        continuation.resume(returning: days)
      }
      store.execute(query)
    }
  }

  func sleepIntervals(since start: Date) async throws -> [SleepInterval] {
    let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
    let type = HKCategoryType(.sleepAnalysis)
    return try await withCheckedThrowingContinuation { continuation in
      let query = HKSampleQuery(
        sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil
      ) { _, results, error in
        guard let results else {
          return continuation.resume(throwing: error ?? CancellationError())
        }
        continuation.resume(
          returning: results.compactMap { $0 as? HKCategorySample }.compactMap { sample in
            SleepStage(rawValue: sample.value).map { (sample.startDate, sample.endDate, $0) }
          })
      }
      store.execute(query)
    }
  }

  /// HKAnchoredObjectQuery: from `start` the first time, then every change after the anchor.
  func changes(of type: HealthType, after anchor: Data?, since start: Date, limit: Int)
    async throws -> HealthChanges
  {
    let previous = anchor.flatMap {
      try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
    }
    let predicate = previous == nil ? HKQuery.predicateForSamples(withStart: start, end: nil) : nil
    let result = try await HKAnchoredObjectQueryDescriptor(
      predicates: [.sample(type: type.sampleType, predicate: predicate)], anchor: previous,
      limit: limit
    ).result(for: store)
    let identifier = type.sampleType.identifier
    return (
      result.addedSamples.compactMap { Self.syncSample($0, type) },
      result.deletedObjects.map { SyncDeletion(uuid: $0.uuid.uuidString, type: identifier) },
      try? NSKeyedArchiver.archivedData(
        withRootObject: result.newAnchor, requiringSecureCoding: true)
    )
  }

  /// Quantities in the type's unit, categories' raw value, workouts' details in metadata.
  private static func syncSample(_ sample: HKSample, _ type: HealthType) -> SyncSample? {
    var value: Double?
    var metadata = (sample.metadata ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
    if let quantity = sample as? HKQuantitySample, let unit = type.unit {
      value = quantity.quantity.doubleValue(for: unit)
    } else if let category = sample as? HKCategorySample {
      value = Double(category.value)
    } else if let workout = sample as? HKWorkout {
      let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()
      metadata["activity_type"] = Double(workout.workoutActivityType.rawValue)
      metadata["duration_s"] = workout.duration
      metadata["total_energy_kcal"] = energy?.doubleValue(for: .kilocalorie())
    } else {
      return nil
    }
    let source = sample.sourceRevision.source
    return SyncSample(
      uuid: sample.uuid.uuidString, type: sample.sampleType.identifier,
      start: SyncSample.timestamp(sample.startDate), end: SyncSample.timestamp(sample.endDate),
      value: value, unit: type.unit?.unitString, sourceName: source.name,
      sourceBundle: source.bundleIdentifier, metadata: metadata.isEmpty ? nil : metadata)
  }

  private func query(_ type: HealthType, predicate: NSPredicate?, limit: Int, newest: Bool)
    async throws -> [HealthSample]
  {
    try await withCheckedThrowingContinuation { continuation in
      let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: !newest)
      let query = HKSampleQuery(
        sampleType: type.sampleType, predicate: predicate, limit: limit, sortDescriptors: [sort]
      ) { _, results, error in
        guard let results else {
          return continuation.resume(throwing: error ?? CancellationError())
        }
        continuation.resume(
          returning: results.map {
            let source = $0.sourceRevision.source
            let value = ($0 as? HKQuantitySample).flatMap { sample in
              type.unit.map { sample.quantity.doubleValue(for: $0) }
            }
            // A workout is dated by its start, so S-023 can match it to a Stezu session.
            return HealthSample(
              type: type, date: type == .workout ? $0.startDate : $0.endDate,
              sourceName: source.name,
              sourceBundleID: source.bundleIdentifier, value: value)
          })
      }
      store.execute(query)
    }
  }

  /// Only samples this app wrote, ending at `date` (weigh-ins start and end at once).
  func deleteBodyMass(at date: Date) async throws {
    let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      HKQuery.predicateForObjects(from: HKSource.default()),
      HKQuery.predicateForSamples(withStart: date, end: date + 1, options: .strictStartDate),
    ])
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      store.deleteObjects(of: HKQuantityType(.bodyMass), predicate: predicate) { _, _, error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
  }
}

extension HealthType {
  /// The HealthKit type behind each v1 type.
  var sampleType: HKSampleType {
    switch self {
    case .bodyMass: HKQuantityType(.bodyMass)
    case .stepCount: HKQuantityType(.stepCount)
    case .heartRate: HKQuantityType(.heartRate)
    case .heartRateVariability: HKQuantityType(.heartRateVariabilitySDNN)
    case .restingHeartRate: HKQuantityType(.restingHeartRate)
    case .sleepAnalysis: HKCategoryType(.sleepAnalysis)
    case .dietaryEnergy: HKQuantityType(.dietaryEnergyConsumed)
    case .dietaryProtein: HKQuantityType(.dietaryProtein)
    case .workout: HKObjectType.workoutType()
    case .oxygenSaturation: HKQuantityType(.oxygenSaturation)
    case .respiratoryRate: HKQuantityType(.respiratoryRate)
    case .bodyTemperature: HKQuantityType(.bodyTemperature)
    case .wristTemperature: HKQuantityType(.appleSleepingWristTemperature)
    }
  }

  /// The unit values are read and synced in; nil for sleep and workouts.
  var unit: HKUnit? {
    switch self {
    case .bodyMass: .pound()
    case .stepCount: .count()
    case .heartRate, .restingHeartRate, .respiratoryRate: .count().unitDivided(by: .minute())
    case .oxygenSaturation: .percent()
    case .bodyTemperature, .wristTemperature: .degreeFahrenheit()
    case .heartRateVariability: .secondUnit(with: .milli)
    case .dietaryEnergy: .kilocalorie()
    case .dietaryProtein: .gram()
    case .sleepAnalysis, .workout: nil
    }
  }
}
