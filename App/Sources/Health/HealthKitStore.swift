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

  /// v1 reads for the Data area. HRV and sleep are context only.
  static var readTypes: Set<HKObjectType> {
    [
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
            return HealthSample(
              type: type, date: $0.endDate, sourceName: source.name,
              sourceBundleID: source.bundleIdentifier)
          })
      }
      store.execute(query)
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
    }
  }
}
