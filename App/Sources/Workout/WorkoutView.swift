import StezuCore
import SwiftUI
import UniformTypeIdentifiers

/// The Workout area: the next template in the rotation as the black card, a row for each other
/// template and Empty workout, and this week's numbers. Start opens the logger. Keep the
/// "screen.workout.title" id on the title; the smoke UI test finds it.
struct WorkoutView: View {
  var goHome: () -> Void = {}
  @Environment(\.appEnvironment) private var environment
  @State private var library: TemplateLibrary?
  @State private var active: WorkoutTemplate?
  @State private var picking = false
  @State private var importMessage: String?
  /// Finished sessions (S-008), oldest first; loaded once, appended on each Finish.
  @State private var finished: [FinishedWorkout]?

  private static let emptyWorkout = WorkoutTemplate(
    key: "empty", name: "Empty workout", exercises: [])

  var body: some View {
    AreaScaffold(area: .workout, title: "Workout", goHome: goHome) {
      if let active {
        WorkoutLoggerView(
          template: active,
          history: environment.workoutHistory + (finished ?? []).map(\.session),
          onFinish: finish)
      } else {
        ScrollView { today }
      }
    }
    .onAppear {
      if library == nil {
        library = WorkoutTemplateStore(storage: environment.storage).load()
      }
      if finished == nil {
        finished = FinishedWorkoutStore(storage: environment.storage).load()
      }
    }
    .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { result in
      importProgram((try? result.get()).flatMap(WorkoutTemplateStore.read))
    }
  }

  private func importProgram(_ data: Data?) {
    let store = WorkoutTemplateStore(storage: environment.storage)
    var updated = library ?? store.load()
    importMessage = store.importProgram(data, into: &updated)
    library = updated
  }

  /// Closes the logger at once, then writes the session to Health and keeps it either way.
  /// A session with no sets is discarded.
  private func finish(_ session: WorkoutSession) {
    active = nil
    WorkoutSessionStore(storage: environment.storage).clear()
    let (health, storage) = (environment.healthStore, environment.storage)
    Task {
      guard let done = await WorkoutFinish.finish(session, at: Date(), health: health) else {
        return
      }
      var updated = finished ?? FinishedWorkoutStore(storage: storage).load()
      updated.append(done)
      finished = updated
      FinishedWorkoutStore(storage: storage).save(updated)
      environment.syncHermesInBackground()
    }
  }

  @ViewBuilder
  private var today: some View {
    // No session history is stored yet, so the rotation starts at the first template.
    let next = library?.next(after: nil)
    let others = (library?.templates ?? []).filter { $0.key != next?.key } + [Self.emptyWorkout]
    let week = WorkoutFinish.week(containing: Date(), in: finished ?? [])
    VStack(alignment: .leading, spacing: 12) {
      if let next { nextCard(next) }
      HStack(spacing: 12) {
        stat("Sessions this week", week.isEmpty ? nil : week.count, id: "workout.week.sessions")
        stat(
          "Working sets", week.isEmpty ? nil : week.reduce(0) { $0 + $1.workingSets },
          id: "workout.week.sets")
      }
      ForEach(Array(week.enumerated()), id: \.offset) { index, workout in
        sessionRow(workout, id: "workout.session.\(index)")
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
      // Above the button, so it shows where the button was when the list ends below the fold.
      if let importMessage {
        Text(importMessage)
          .font(.system(size: Theme.labelSize))
          .foregroundStyle(Theme.text)
          .accessibilityIdentifier("workout.import.message")
      }
      Button {
        switch environment.programFilePicker {
        case .files: picking = true
        case .fixture(let data): importProgram(data)
        }
      } label: {
        Text("Import program")
          .font(.system(size: Theme.subtitleSize))
          .foregroundStyle(Theme.label)
          .frame(maxWidth: .infinity, minHeight: 48)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("workout.import")
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

  /// A finished session this week: its template, sets, and whether Health has it.
  private func sessionRow(_ workout: FinishedWorkout, id: String) -> some View {
    let key = workout.session.templateKey
    let name = library?.templates.first(where: { $0.key == key })?.name ?? "Workout"
    let sets = workout.workingSets
    return HStack {
      Text("\(name)   \(sets) \(sets == 1 ? "set" : "sets")")
        .font(.system(size: Theme.subtitleSize))
        .foregroundStyle(Theme.text)
        .accessibilityIdentifier(id)
      Spacer()
      Text(workout.inHealth ? "In Health" : "Not in Health")
        .font(.system(size: Theme.labelSize))
        .foregroundStyle(Theme.label)
        .accessibilityIdentifier("\(id).health")
    }
    .padding(16)
    .background(card(inverted: false))
  }

  /// A weekly number; with no finished session this week it is missing: "--", never 0.
  private func stat(_ label: String, _ value: Int?, id: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.system(size: Theme.labelSize)).foregroundStyle(Theme.label)
      Text(value.map(String.init) ?? "--")
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
