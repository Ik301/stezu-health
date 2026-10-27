import StezuCore
import SwiftUI

/// This week's logged food as ranges and this week's sessions from Stezu and Health (S-023).
/// No meals or no workouts this week show "--", never 0.
struct WeeklyFoodWorkoutRows: View {
  @Environment(\.appEnvironment) private var environment
  @State private var food: WeeklyFood?
  @State private var workouts: [WeekWorkout]?

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spaceSm) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: Theme.space2xs) {
          Text("Food").textStyle(.headline)
          label(food.map { "logged \($0.loggedDays) of 7 days" } ?? "--")
            .accessibilityIdentifier("data.food.coverage")
        }
        Spacer()
        VStack(alignment: .trailing, spacing: Theme.space2xs) {
          value(food?.kcal, unit: "kcal").accessibilityIdentifier("data.food.kcal")
          value(food?.protein, unit: "g protein").accessibilityIdentifier("data.food.protein")
        }
      }
      HStack(alignment: .firstTextBaseline) {
        Text("Workouts").textStyle(.headline)
        Spacer()
        Text(workouts.flatMap { $0.isEmpty ? nil : "\($0.count) this week" } ?? "--")
          .textStyle(.value).accessibilityIdentifier("data.workouts.value")
      }
      ForEach(Array((workouts ?? []).enumerated()), id: \.offset) { index, workout in
        HStack {
          Text(workout.start.formatted(.dateTime.weekday(.abbreviated)) + "  " + workout.detail)
            .accessibilityIdentifier("data.workouts.\(index)")
          Spacer()
          label(workout.source.rawValue).accessibilityIdentifier("data.workouts.\(index).source")
        }
        .textStyle(.subtitle)
      }
    }
    .foregroundStyle(Theme.ink)
    .padding(Theme.spaceLg)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
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
  }

  private func value(_ stat: WeeklyRange?, unit: String) -> some View {
    Text(stat?.value.map { PhotoMatchSheet.range($0, unit: unit) } ?? "--")
      .textStyle(.value)
  }

  private func label(_ text: String) -> some View {
    Text(text).textStyle(.label).foregroundStyle(Theme.muted)
  }
}
