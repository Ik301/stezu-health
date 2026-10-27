import HealthKit
import StezuCore

/// A continued session's Health workout is replaced (S-036, D-090): Finish deletes the one this
/// app wrote for the session's id, then saves a new one.
extension HealthKitStore {
  /// Only workouts from this app with that external id; none found is not an error.
  func deleteStrengthWorkout(externalID: String) async throws {
    let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      HKQuery.predicateForObjects(from: HKSource.default()),
      HKQuery.predicateForObjects(
        withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [externalID]),
    ])
    _ = try await HKHealthStore().deleteObjects(
      of: HKObjectType.workoutType(), predicate: predicate)
  }
}
