import StezuCore
import XCTest

/// S-059: recipes, a saved ingredient list logged as an ordinary meal. All values are made up
/// (D-034).
final class RecipeTests: XCTestCase {
  private func item(_ name: String, kcal: Double, protein: Double) throws -> MatchedItem {
    try PhotoMatchClient.decode(
      Data(
        #"""
        {"meal_id": "x", "items": [{"item_id": "\#(name)", "name": "\#(name)", "servings": 1,
         "kcal": {"low": \#(kcal), "high": \#(kcal * 2)},
         "protein_g": {"low": \#(protein), "high": \#(protein * 2)}}]}
        """#.utf8)
    ).items[0]
  }

  private let start = Date(timeIntervalSince1970: 1_800_000_000)

  func testTotalsFollowIngredients() throws {
    var recipe = Recipe(name: "Mix", items: [], at: start)
    XCTAssertNil(recipe.totalKcal, "no ingredients is unknown, not 0")
    recipe.items = [
      try item("Oats", kcal: 100, protein: 4), try item("Milk", kcal: 50, protein: 8),
    ]
    XCTAssertEqual(recipe.totalKcal, FoodRange(low: 150, high: 300))
    XCTAssertEqual(recipe.totalProteinG, FoodRange(low: 12, high: 24))
    var edit = MealEdit(recipe.meal(id: UUID()))
    edit.step(1, up: true)
    recipe.items = edit.items
    XCTAssertEqual(recipe.totalKcal, FoodRange(low: 175, high: 350))
    edit.remove(0)
    recipe.items = edit.items
    XCTAssertEqual(recipe.totalProteinG, FoodRange(low: 12, high: 24))
    XCTAssertEqual(Recipe.name("  Shake "), "Shake")
    XCTAssertNil(Recipe.name("   "))
    XCTAssertNil(Recipe.name(String(repeating: "a", count: 61)))
    XCTAssertEqual(Recipe.name(String(repeating: "a", count: 60))?.count, 60)
  }

  func testStoreRoundTripsAndDeletes() async throws {
    let written = Written()
    let store = RecipeStore { recipes in written.set(recipes) }
    let first = Recipe(name: "One", items: [try item("Oats", kcal: 100, protein: 4)], at: start)
    let second = Recipe(name: "Two", items: [try item("Milk", kcal: 50, protein: 8)], at: start)
    await store.set(first, at: start)
    await store.set(second, at: start + 60)
    var renamed = first
    renamed.name = "One, renamed"
    let saved = await store.set(renamed, at: start + 120)
    XCTAssertEqual(saved.map(\.name), ["One, renamed", "Two"], "an edit keeps its place")
    XCTAssertEqual(saved[0].createdAt, start)
    XCTAssertEqual(saved[0].updatedAt, start + 120)

    let data = try JSONEncoder().encode(written.value)
    let loaded = try JSONDecoder().decode([Recipe].self, from: data)
    XCTAssertEqual(loaded, saved, "recipes.json round-trips")
    let reopened = RecipeStore(loaded)
    let left = await reopened.set(second, delete: true, at: start + 180)
    XCTAssertEqual(left.map(\.name), ["One, renamed"])
    let none = await reopened.set(renamed, delete: true, at: start + 240)
    XCTAssertTrue(none.isEmpty)
  }

  func testLoggingCopiesItemsWithoutChangingRecipe() async throws {
    let store = RecipeStore()
    let recipe = Recipe(name: "Bowl", items: [try item("Rice", kcal: 100, protein: 2)], at: start)
    await store.set(recipe, at: start)
    let mealID = UUID()
    let match = recipe.meal(id: mealID)
    XCTAssertEqual(match.mealId, mealID.uuidString)
    XCTAssertEqual(match.items, recipe.items)
    var edit = MealEdit(match)
    edit.step(0, up: true)
    let meal = LoggedMeal(id: mealID, loggedAt: start, items: edit.items)
    XCTAssertEqual(meal.items[0].servings, 1.5)
    let kept = await store.recipes
    XCTAssertEqual(kept[0].items[0].servings, 1, "the meal's serving change left the recipe")
    XCTAssertEqual(kept[0].totalKcal, FoodRange(low: 100, high: 200))

    var renamed = recipe
    renamed.items = []
    await store.set(renamed, at: start + 60)
    await store.set(renamed, delete: true, at: start + 120)
    XCTAssertEqual(meal.items[0].kcal, FoodRange(low: 150, high: 300), "the logged meal stays")
  }
}

/// What the store last wrote.
private final class Written: @unchecked Sendable {
  private let lock = NSLock()
  private var recipes: [Recipe] = []
  var value: [Recipe] { lock.withLock { recipes } }
  func set(_ recipes: [Recipe]) { lock.withLock { self.recipes = recipes } }
}
