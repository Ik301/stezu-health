import StezuCore
import SwiftUI

/// The Workout area: the next template in the rotation as the black card, a row for each other
/// template and Empty workout, and this week's numbers. Start opens the logger. Keep the
/// "screen.workout.title" id on the title; the smoke UI test finds it.
struct WorkoutView: View {
  var goHome: () -> Void = {}
  @Environment(\.appEnvironment) private var environment
  @State private var library: TemplateLibrary?
  @State private var active: WorkoutTemplate?

  private static let emptyWorkout = WorkoutTemplate(
    key: "empty", name: "Empty workout", exercises: [])

  var body: some View {
    AreaScaffold(area: .workout, title: "Workout", goHome: goHome) {
      if let active {
        WorkoutLoggerView(template: active, history: environment.workoutHistory)
      } else {
        ScrollView { today }
      }
    }
    .onAppear {
      if library == nil {
        library = WorkoutTemplateStore(storage: environment.storage).load()
      }
    }
  }

  @ViewBuilder
  private var today: some View {
    // No session history is stored yet, so the rotation starts at the first template.
    let next = library?.next(after: nil)
    let others = (library?.templates ?? []).filter { $0.key != next?.key } + [Self.emptyWorkout]
    VStack(alignment: .leading, spacing: 12) {
      if let next { nextCard(next) }
      HStack(spacing: 12) {
        stat("Sessions this week", id: "workout.week.sessions")
        stat("Working sets", id: "workout.week.sets")
      }
      ForEach(others, id: \.key) { template in
        Button {
          active = template
        } label: {
          Text(template.name)
            .font(.system(size: Theme.subtitleSize))
            .foregroundStyle(Theme.text)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(card(inverted: false))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workout.template.\(template.key)")
      }
    }
  }

  private func nextCard(_ template: WorkoutTemplate) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(template.name)
        .font(.system(size: 28, weight: .semibold))
        .accessibilityIdentifier("workout.today.name")
      ForEach(Array(template.exercises.enumerated()), id: \.offset) { index, exercise in
        Text("\(exercise.name)  \(exercise.sets) x \(exercise.repRange)")
          .font(.system(size: Theme.subtitleSize))
          .accessibilityIdentifier("workout.today.exercise.\(index)")
      }
      Button {
        active = template
      } label: {
        Text("Start")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(Theme.text)
          .frame(maxWidth: .infinity, minHeight: 48)
          .background(Capsule().fill(Theme.invertedText))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("workout.today.start")
    }
    .foregroundStyle(Theme.invertedText)
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(card(inverted: true))
  }

  /// A weekly number. No sessions are stored yet, so it is missing: "--", never 0.
  private func stat(_ label: String, id: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.system(size: Theme.labelSize)).foregroundStyle(Theme.label)
      Text("--")
        .font(.system(size: Theme.bigNumberSize, weight: .medium))
        .tracking(Theme.bigNumberTracking)
        .foregroundStyle(Theme.text)
        .accessibilityIdentifier(id)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(card(inverted: false))
  }

  private func card(inverted: Bool) -> some View {
    let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
    return shape.fill(inverted ? Theme.invertedCard : Theme.card)
      .overlay(shape.strokeBorder(inverted ? Color.clear : Theme.cardBorder, lineWidth: 1))
  }
}

#Preview {
  WorkoutView()
}
