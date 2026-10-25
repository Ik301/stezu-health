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
}
