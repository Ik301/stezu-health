import Foundation
import StezuCore

/// What the Home cards track (S-026): this week's weight, today's food, this week's sessions and
/// the next template. Each is nil until it exists (absent, not zero). No targets (D-032).
struct HomeInputs: Sendable, Equatable {
  var weight: WeekWeight?
  var food: FoodDay?
  /// This week's sessions, Stezu and Health merged as on Data (S-023).
  var workouts: [WeekWorkout]?
  /// The name of the template the Workout area offers next.
  var nextTemplate: String?

  /// Reads every input from the launch's services; a read that fails is absent.
  static func load(from environment: AppEnvironment) async -> HomeInputs {
    let now = environment.now()
    let week = WeeklyStats.week(containing: now)
    let meals = await environment.mealCaptures.logged() + environment.mealHistory
    let finished = FinishedWorkoutStore(storage: environment.storage).load().map(\.session)
    let health = (try? await environment.healthStore.samples(of: .workout, since: week.start)) ?? []
    let library = WorkoutTemplateStore(storage: environment.storage).load()
    return HomeInputs(
      weight: await WeeklyWeight.load(from: environment.weightHealth, now: now).week,
      food: FoodDay.on(now, meals: meals),
      workouts: WeeklyIntake.workouts(
        stezu: environment.workoutHistory + finished, health: health, in: week),
      nextTemplate: library.next(after: nil)?.name)
  }
}

/// Builds the Data, Food and Workout cards and picks the inverted one from an injected clock.
struct HomeViewModel: Sendable {
  static let missing = "--"

  /// Start hour and card id; a card stays inverted until the next start. Hours before the
  /// first start belong to the last entry. These are defaults, not personal numbers.
  static let defaultSchedule: [(hour: Int, cardID: String)] = [
    (5, "data"), (11, "food"), (16, "workout"), (20, "food"),
  ]

  var calendar: Calendar = .current
  var schedule: [(hour: Int, cardID: String)] = HomeViewModel.defaultSchedule
  var now: @Sendable () -> Date = { Date() }

  func cards(_ inputs: HomeInputs) -> [HomeCard] {
    [dataCard(inputs), foodCard(inputs), workoutCard(inputs)]
  }

  /// The id of the "log this now" card for the clock's current hour.
  func invertedCardID() -> String? {
    let hour = calendar.component(.hour, from: now())
    let sorted = schedule.sorted { $0.hour < $1.hour }
    return (sorted.last { $0.hour <= hour } ?? sorted.last)?.cardID
  }

  /// The trend weight as the number, weigh-in days this week out of 7 below it.
  private func dataCard(_ inputs: HomeInputs) -> HomeCard {
    let week = inputs.weight
    let days = week?.daysWeighed.map { "\($0) of 7" } ?? Self.missing
    return HomeCard(
      id: "data", label: "Data", subtitle: "Trend weight, lb. Weigh-ins \(days)",
      value: week?.trend.map { String(format: "%.1f", $0) } ?? Self.missing,
      confidence: week?.trend == nil ? nil : week?.confidence)
  }

  /// Today's kcal range as the number, the protein range and meal count below it.
  private func foodCard(_ inputs: HomeInputs) -> HomeCard {
    let day = inputs.food
    let protein = day?.proteinG.map(Self.range) ?? Self.missing
    let meals = day?.mealCount.map { "\($0) meal\($0 == 1 ? "" : "s")" } ?? "\(Self.missing) meals"
    return HomeCard(
      id: "food", label: "Food", subtitle: "Today, kcal. \(protein) g protein, \(meals)",
      value: day?.kcal.map(Self.range) ?? Self.missing,
      confidence: day?.kcal == nil ? nil : day?.confidence)
  }

  /// Sessions this week as the number, the next template below it.
  private func workoutCard(_ inputs: HomeInputs) -> HomeCard {
    let sessions = inputs.workouts.flatMap { $0.isEmpty ? nil : $0 }
    let confidence = sessions.map { all in
      let stezu = all.filter { $0.source == .stezu }.count
      return Confidence(
        level: .high, reason: "\(stezu) from Stezu, \(all.count - stezu) from Health")
    }
    return HomeCard(
      id: "workout", label: "Workout",
      subtitle: "Sessions this week. Next: \(inputs.nextTemplate ?? Self.missing)",
      value: sessions.map { String($0.count) } ?? Self.missing, confidence: confidence)
  }

  /// "330-450": a range in whole numbers, independent of the device locale.
  private static func range(_ range: FoodRange) -> String {
    "\(Int(range.low.rounded()))-\(Int(range.high.rounded()))"
  }
}
