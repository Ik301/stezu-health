import Foundation

/// S-059 (D-149): a named list of the same items meals use, at their servings, kept on the phone
/// in recipes.json. Never synced and never written to Health; logging one copies its items into
/// an ordinary meal.
public struct Recipe: Codable, Sendable, Equatable, Identifiable {
  public static let maxName = 60
  public let id: UUID
  public var name: String
  public var items: [MatchedItem]
  public var createdAt, updatedAt: Date

  public init(id: UUID = UUID(), name: String, items: [MatchedItem], at now: Date) {
    (self.id, self.name, self.items, createdAt, updatedAt) = (id, name, items, now, now)
  }

  public var totalKcal: FoodRange? { FoodRange.total(items.map(\.kcal)) }
  public var totalProteinG: FoodRange? { FoodRange.total(items.map(\.proteinG)) }

  /// A name trimmed to 1 to 60 characters, or nil, which keeps Save disabled.
  public static func name(_ text: String) -> String? {
    let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return (1...maxName).contains(name.count) ? name : nil
  }

  /// The item list a Log starts from: copies of the items under a new meal id, so editing that
  /// meal never touches the recipe.
  public func meal(id: UUID) -> PhotoMatch { PhotoMatch(mealId: id.uuidString, items: items) }
}

/// Holds the recipes, oldest first: a save adds one (created now) or replaces it in place by id,
/// a delete removes it; every change writes the file through `save`.
public actor RecipeStore {
  public private(set) var recipes: [Recipe]
  private let save: @Sendable ([Recipe]) -> Void

  public init(_ recipes: [Recipe] = [], save: @escaping @Sendable ([Recipe]) -> Void = { _ in }) {
    (self.recipes, self.save) = (recipes, save)
  }

  @discardableResult
  public func set(_ recipe: Recipe, delete: Bool = false, at now: Date = Date()) -> [Recipe] {
    var recipe = recipe
    recipe.updatedAt = now
    if let old = recipes.firstIndex(where: { $0.id == recipe.id }) {
      recipe.createdAt = recipes[old].createdAt
      if delete { recipes.remove(at: old) } else { recipes[old] = recipe }
    } else if !delete {
      recipe.createdAt = now
      recipes.append(recipe)
    }
    save(recipes)
    return recipes
  }
}
