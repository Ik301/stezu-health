import StezuCore
import XCTest

/// Food other apps wrote to Health shows beside the phone's meals. All values are made up (D-034).
final class HealthFoodTests: XCTestCase {
  private let noon = Date(timeIntervalSince1970: 1_800_014_400)

  private func sample(
    _ type: HealthType, _ value: Double?, at date: Date, app: String = "Tracker",
    bundle: String? = "example.tracker"
  ) -> HealthSample {
    HealthSample(
      type: type, date: date, sourceName: app, sourceBundleID: bundle, value: value,
      id: UUID().uuidString)
  }

  func testEnergyAndProteinAtOneInstantAreOneMeal() {
    let meals = HealthFood.meals([
      sample(.dietaryEnergy, 520, at: noon), sample(.dietaryProtein, 31, at: noon),
      sample(.dietaryEnergy, 200, at: noon - 3600),
    ])
    XCTAssertEqual(meals.count, 2)
    XCTAssertEqual(meals[0].loggedAt, noon - 3600)
    XCTAssertEqual(meals[0].items[0].kcal, FoodRange(low: 200, high: 200))
    XCTAssertNil(meals[0].items[0].proteinG, "missing protein is absent, not 0")
    XCTAssertEqual(meals[1].items[0].kcal, FoodRange(low: 520, high: 520))
    XCTAssertEqual(meals[1].items[0].proteinG, FoodRange(low: 31, high: 31))
    XCTAssertEqual(meals[1].items[0].brand, "Tracker")
    XCTAssertEqual(meals[1].inHealth, true)
    XCTAssertTrue(meals.allSatisfy(\.isFromHealth))
  }

  func testStezuOwnEntriesAndOtherTypesAreSkipped() {
    let meals = HealthFood.meals([
      sample(.dietaryEnergy, 400, at: noon, app: "Stezu", bundle: WeeklyWeight.stezuBundleID),
      sample(.bodyMass, 170, at: noon), sample(.dietaryEnergy, nil, at: noon),
    ])
    XCTAssertTrue(meals.isEmpty, "Stezu's copies, weights and empty reads are not meals")
  }

  func testTwoAppsAtOneInstantStaySeparate() {
    let meals = HealthFood.meals([
      sample(.dietaryEnergy, 300, at: noon),
      sample(.dietaryEnergy, 100, at: noon, app: "Other", bundle: "example.other"),
    ])
    XCTAssertEqual(meals.count, 2)
    XCTAssertEqual(FoodDay.on(noon, meals: meals).kcal, FoodRange(low: 400, high: 400))
  }

  func testLoggedMealIsNotFromHealth() throws {
    let reply = #"{"meal_id": "m", "items": [{"item_id": "a", "name": "Bowl", "servings": 1}]}"#
    let items = try PhotoMatchClient.decode(Data(reply.utf8)).items
    XCTAssertFalse(LoggedMeal(id: UUID(), loggedAt: noon, items: items).isFromHealth)
  }
}
