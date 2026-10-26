import Foundation

/// A logged meal as Apple Health keeps it (S-018): one food correlation holding dietary energy
/// and protein. Each holds its range's midpoint, with the low and high in its metadata; the meal
/// id is the correlation's sync identifier, so a second write of the same meal replaces the first.
public struct FoodEntry: Sendable, Equatable {
  public let syncIdentifier: String
  public let date: Date
  /// The meal totals; nil when an item has no range (the quantity is then not written).
  public let kcal: FoodRange?
  public let proteinG: FoodRange?

  public init(meal: LoggedMeal) {
    syncIdentifier = meal.id.uuidString
    date = meal.loggedAt
    kcal = FoodRange.total(meal.items.map(\.kcal))
    proteinG = FoodRange.total(meal.items.map(\.proteinG))
  }

  /// Metadata keys for the energy sample and the protein sample.
  public static let kcalKeys = (low: "stezu_kcal_low", high: "stezu_kcal_high")
  public static let proteinKeys = (low: "stezu_protein_g_low", high: "stezu_protein_g_high")
}

extension FoodRange {
  public var midpoint: Double { (low + high) / 2 }

  /// The low and high under these metadata keys.
  public func metadata(_ keys: (low: String, high: String)) -> [String: Double] {
    [keys.low: low, keys.high: high]
  }
}

public enum MealHealth {
  public enum Failure: Error { case nothingToWrite }

  /// Saves the meal on the phone first, then writes it to Health and saves its Health state. A
  /// failed local save throws before anything reaches Health. A denied or failed Health write
  /// keeps the meal, with `inHealth` false.
  public static func log(
    _ meal: LoggedMeal, health: any HealthStore,
    save: @Sendable (LoggedMeal) async throws -> Void
  ) async throws -> LoggedMeal {
    try await save(meal)
    var written = meal
    do {
      let entry = FoodEntry(meal: meal)
      guard entry.kcal != nil || entry.proteinG != nil else { throw Failure.nothingToWrite }
      try await health.saveFood(entry)
      written.inHealth = true
    } catch {
      written.inHealth = false
    }
    try? await save(written)
    return written
  }

  /// An edit (S-019): saved on the phone, old Health entry deleted, then written as `log` does.
  public static func replace(
    _ meal: LoggedMeal, health: any HealthStore,
    save: @Sendable (LoggedMeal) async throws -> Void
  ) async throws -> LoggedMeal {
    try await save(meal)
    try? await health.deleteFood(syncIdentifier: meal.id.uuidString)
    return try await log(meal, health: health, save: save)
  }

  /// A delete: the meal leaves the phone, then Health. False when Health kept its entry.
  public static func delete(
    _ id: UUID, health: any HealthStore, remove: @Sendable (UUID) async -> Void
  ) async -> Bool {
    await remove(id)
    return (try? await health.deleteFood(syncIdentifier: id.uuidString)) != nil
  }
}
