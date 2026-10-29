import Foundation

/// Food that other apps wrote to Apple Health, shown beside the meals logged here. Stezu's own
/// Health entries are copies of the phone's meals (D-072), so they are skipped. Each app's energy
/// and protein written at the same instant are one meal, with exact values as a zero-width range.
public enum HealthFood {
  /// The item id that marks a meal read from Health; such a meal is read-only here.
  public static let itemID = "health"

  /// One meal per app and instant, oldest first; samples of other types and without a value are
  /// ignored. A meal with energy but no protein (or the reverse) keeps the missing one absent.
  public static func meals(_ samples: [HealthSample]) -> [LoggedMeal] {
    let food = samples.filter { sample in
      (sample.type == .dietaryEnergy || sample.type == .dietaryProtein) && sample.value != nil
        && sample.sourceBundleID != WeeklyWeight.stezuBundleID
    }
    let entries = Dictionary(grouping: food) { "\($0.sourceBundleID ?? $0.sourceName)|\($0.date)" }
    return entries.values.compactMap { group -> LoggedMeal? in
      guard let first = group.first else { return nil }
      func range(_ type: HealthType) -> FoodRange? {
        let values = group.filter { $0.type == type }.compactMap(\.value)
        let sum = values.reduce(0, +)
        return values.isEmpty ? nil : FoodRange(low: sum, high: sum)
      }
      let item = MatchedItem(
        itemId: itemID, name: "Food from Health", hall: nil, halls: nil, brand: first.sourceName,
        serving: nil, servings: nil, confidence: nil, rough: nil, kcal: range(.dietaryEnergy),
        proteinG: range(.dietaryProtein))
      let id = group.compactMap { $0.id.flatMap(UUID.init(uuidString:)) }
        .min { $0.uuidString < $1.uuidString }
      var meal = LoggedMeal(id: id ?? UUID(), loggedAt: first.date, items: [item])
      meal.inHealth = true
      return meal
    }
    .sorted { $0.loggedAt < $1.loggedAt }
  }
}

extension LoggedMeal {
  /// Read from Health and written by another app, so it is not edited or deleted here.
  public var isFromHealth: Bool {
    !items.isEmpty && items.allSatisfy { $0.itemId == HealthFood.itemID }
  }
}
