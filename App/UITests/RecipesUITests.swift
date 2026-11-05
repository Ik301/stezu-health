import XCTest

/// S-059: Recipes beside History. Make "Shake" from one search pick and one scanned product
/// (the fake transport's made-up items), change a serving, Save; the row shows its totals. Tap it
/// and Log: the camera strip counts one more meal. Then rename it through Edit and delete it.
final class RecipesUITests: XCTestCase {
  @MainActor
  func testMakeRecipeThenLogIt() {
    continueAfterFailure = false
    let app = UITestApp.launch()
    let card = app.element("home.card.food")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no food card on Home")
    card.tap()
    let meals = app.element("food.strip.meals")
    XCTAssertTrue(meals.waitForExistence(timeout: 10), "no today strip")
    let before = meals.label

    // Step 1: Recipes opens the list; none saved yet.
    app.element("food.recipes").tap()
    XCTAssertTrue(app.element("food.recipes.list").waitForExistence(timeout: 5), "no Recipes")
    XCTAssertTrue(app.element("food.recipes.empty").exists, "no empty state")
    XCTAssertEqual(app.element("food.recipes.empty").label, "No recipes yet")

    // Step 2: + New recipe; Save waits for a name and an ingredient.
    app.element("food.recipes.new").tap()
    XCTAssertTrue(app.element("food.recipe.editor").waitForExistence(timeout: 5), "no editor")
    let save = app.element("food.recipe.save")
    XCTAssertFalse(save.isEnabled, "Save before a name and an item")
    let name = app.element("food.recipe.name")
    name.tap()
    name.typeText("Shake\n")
    XCTAssertFalse(save.isEnabled, "Save with no ingredient")

    // One search pick, then one scanned product.
    app.element("food.edit.add").tap()
    let field = app.element("food.edit.search.field")
    XCTAssertTrue(field.waitForExistence(timeout: 5), "search did not open")
    field.tap()
    field.typeText("yogurt\n")
    let result = app.element("food.search.result.open_food_facts.0.name")
    XCTAssertTrue(result.waitForExistence(timeout: 10), "no search result")
    result.tap()
    XCTAssertTrue(app.element("food.match.item.0.name").waitForExistence(timeout: 10))
    XCTAssertEqual(app.element("food.match.item.0.name").label, "Plain Yogurt")
    XCTAssertTrue(save.isEnabled, "Save stays off with a name and an item")
    app.element("food.recipe.barcode").tap()
    let scanned = app.element("food.match.item.1.name")
    XCTAssertTrue(scanned.waitForExistence(timeout: 20), "the scanned product did not join")
    XCTAssertEqual(scanned.label, "Oat Bar")
    XCTAssertEqual(app.element("food.match.total.kcal").label, "195–325 kcal")

    // Change a serving: the totals follow.
    app.element("food.match.item.0.plus").tap()
    app.element("food.match.item.0.plus").tap()
    XCTAssertEqual(app.element("food.match.item.0.servings").label, "2 x 1 cup")
    XCTAssertEqual(app.element("food.match.total.kcal").label, "270–450 kcal")
    XCTAssertEqual(app.element("food.match.total.protein").label, "27–45 g protein")
    saveScreenshot("s059-recipe-editor", of: app)
    save.tap()

    // The row shows the name, the totals and the item count.
    let row = app.element("food.recipes.row.0.name")
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no recipe row")
    XCTAssertEqual(row.label, "Shake")
    XCTAssertEqual(app.element("food.recipes.row.0.kcal").label, "270–450 kcal")
    XCTAssertEqual(app.element("food.recipes.row.0.protein").label, "27–45 g protein")
    XCTAssertEqual(app.element("food.recipes.row.0.count").label, "2 items")
    XCTAssertFalse(app.element("food.recipes.empty").exists)
    saveScreenshot("s059-recipe-list", of: app)

    // Step 4: tap it and Log; the strip counts one more meal.
    row.tap()
    let log = app.element("food.edit.log")
    XCTAssertTrue(log.waitForExistence(timeout: 5), "no Log")
    XCTAssertEqual(app.element("food.match.total.kcal").label, "270–450 kcal")
    log.tap()
    XCTAssertTrue(app.element("food.logged.toast").waitForExistence(timeout: 10), "no toast")
    XCTAssertTrue(app.element("food.shutter").exists, "not back on the camera")
    let count = (Int(before.prefix { $0.isNumber }) ?? 0) + 1
    let after = "\(count) meal\(count == 1 ? "" : "s")"
    expectation(for: NSPredicate(format: "label == %@", after), evaluatedWith: meals)
    waitForExpectations(timeout: 10)

    // Step 5: swipe left, Edit, rename.
    app.element("food.recipes").tap()
    XCTAssertTrue(row.waitForExistence(timeout: 5), "the recipe is gone")
    app.element("food.recipes.row.0").swipeLeft()
    let edit = app.element("food.recipes.row.0.edit")
    XCTAssertTrue(edit.waitForExistence(timeout: 5), "no Edit after a swipe")
    edit.tap()
    XCTAssertTrue(name.waitForExistence(timeout: 5), "the editor did not open")
    XCTAssertEqual(name.value as? String, "Shake")
    name.tap()
    name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "Big shake\n")
    save.tap()
    expectation(for: NSPredicate(format: "label == 'Big shake'"), evaluatedWith: row)
    waitForExpectations(timeout: 10)
    XCTAssertEqual(app.element("food.recipes.row.0.kcal").label, "270–450 kcal")

    // Delete turns into Confirm; the second tap removes it.
    app.element("food.recipes.row.0").swipeLeft()
    let delete = app.element("food.recipes.row.0.delete")
    XCTAssertTrue(delete.waitForExistence(timeout: 5), "no Delete after a swipe")
    delete.tap()
    expectation(for: NSPredicate(format: "label == 'Confirm'"), evaluatedWith: delete)
    waitForExpectations(timeout: 5)
    delete.tap()
    XCTAssertTrue(app.element("food.recipes.empty").waitForExistence(timeout: 5), "not deleted")
    XCTAssertFalse(row.exists)
  }
}
