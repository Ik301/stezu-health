import StezuCore
import SwiftUI

/// This week's Food and Workouts rows (S-023, S-039). Food: the mean kcal range over the logged
/// days, with each day's kcal as data-energy bars. Workouts: sessions from Stezu and Health, the
/// week's working sets beneath, and each day's sets as bars, where a rest day is a real 0. No
/// meals or no sessions this week show "--", never 0.
struct WeeklyFoodWorkoutRows: View {
  var open: (Metric) -> Void = { _ in }
  @Environment(\.appEnvironment) private var environment
  @State private var food: WeeklyFood?
  @State private var workouts: [WeekWorkout]?
  @State private var days: (food: MetricHistory, sets: MetricHistory)?

  var body: some View {
    let sets = days?.sets.weeks.first?.stat.value
    VStack(spacing: 0) {
      MetricRow(
        title: "Food", id: "food", coverage: food.map { "\($0.loggedDays) of 7 days" } ?? "--",
        values: days.map { ChartSeries.sparkline($0.food) } ?? [], color: Theme.dataEnergy,
        value: food?.kcal.value.map(kcal) ?? "--", first: true
      ) { open(.food) }
      MetricRow(
        title: "Workouts", id: "workouts", coverage: sets.map { "\(Int($0)) working sets" } ?? "--",
        values: days.map { ChartSeries.sparkline($0.sets) } ?? [],
        value: workouts.flatMap { $0.isEmpty ? nil : "\($0.count)" } ?? "--"
      ) { open(.workouts) }
    }
    .task { await load() }
  }

  /// Logged meals from the phone (and a scenario's), Stezu sessions from the seeded history and
  /// the finished-workout file, and Health's workouts; a Health read that throws is none.
  private func load() async {
    let week = WeeklyStats.week(containing: environment.now())
    let meals = await environment.mealCaptures.logged() + environment.mealHistory
    food = WeeklyIntake.food(meals, in: week)
    let finished = FinishedWorkoutStore(storage: environment.storage).load().map(\.session)
    let health = (try? await environment.healthStore.samples(of: .workout, since: week.start)) ?? []
    workouts = WeeklyIntake.workouts(
      stezu: environment.workoutHistory + finished, health: health, in: week)
    days = (
      MetricHistory.food(meals, now: environment.now()),
      MetricHistory.workouts(environment.workoutHistory + finished, now: environment.now())
    )
  }

  private func kcal(_ range: FoodRange) -> String {
    "\(Int(range.low.rounded()).formatted())–\(Int(range.high.rounded()).formatted()) kcal"
  }
}
