import StezuCore
import SwiftUI

/// The logger, open on the template's first exercise: its name, "Set 1 of N" and the rep range.
/// Logging, steppers and moving through exercises come with the next Workout stories.
struct WorkoutLoggerView: View {
  let template: WorkoutTemplate

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      let exercise = template.exercises.first
      Text(exercise?.name ?? "No exercises")
        .font(.system(size: 28, weight: .semibold))
        .accessibilityIdentifier("workout.logger.exercise")
      Text(exercise.map { "Set 1 of \($0.sets)" } ?? "--")
        .font(.system(size: Theme.subtitleSize))
        .accessibilityIdentifier("workout.logger.set")
      Text(exercise.map { "\($0.repRange) reps" } ?? "--")
        .font(.system(size: Theme.bigNumberSize, weight: .medium))
        .tracking(Theme.bigNumberTracking)
        .accessibilityIdentifier("workout.logger.reps")
    }
    .foregroundStyle(Theme.invertedText)
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.invertedCard))
  }
}
