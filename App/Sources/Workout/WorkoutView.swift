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
  /// A checked program file waiting for Replace or Cancel (S-034).
  @State private var pending: [WorkoutTemplate]?
  /// Finished sessions (S-008), oldest first; loaded once, appended on each Finish.
  @State private var finished: [FinishedWorkout]?
  /// The saved workout in progress (S-009), offered as Resume in place of the black card.
  @State private var resumable: SetLogger?
  /// The saved logger the open logger was resumed from; nil for a new session.
  @State private var resuming: SetLogger?
  @State private var showHistory = false  // the History sheet (S-010)

  private static let emptyWorkout = WorkoutTemplate(
    key: "empty", name: "Empty workout", exercises: [])

  var body: some View {
    AreaScaffold(area: .workout, title: "Workout", goHome: goHome) {
      if let active {
        WorkoutLoggerView(
          template: active, resuming: resuming,
          history: history, addOns: library?.addOns ?? [],
          onFinish: finish)
      } else {
        ScrollView { today }.scrollIndicators(.hidden)
      }
    }
    .onAppear {
      if library == nil {
        library = WorkoutTemplateStore(storage: environment.storage).load()
      }
      if finished == nil {
        finished = FinishedWorkoutStore(storage: environment.storage).load()
      }
      if active == nil { loadSaved() }
    }
    .sheet(isPresented: $showHistory) {
      WorkoutHistoryView(sessions: history, names: library?.names ?? [:])
    }
    .alert(
      pending.map(WorkoutTemplateStore.question) ?? "",
      isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
      presenting: pending
    ) { templates in
      Button("Replace") { replaceProgram(with: templates) }
        .accessibilityIdentifier("workout.import.replace")
      Button("Cancel", role: .cancel) {}
        .accessibilityIdentifier("workout.import.cancel")
    } message: { _ in
      Text("Your workout history is kept.")
    }
    .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { result in
      importProgram((try? result.get()).flatMap(WorkoutTemplateStore.read))
    }
  }

  /// Past sessions: the seeded ones plus every finished session.
  private var history: [WorkoutSession] {
    environment.workoutHistory + (finished ?? []).map(\.session)
  }

  /// A valid file asks to replace the program; a refused one says why and changes nothing.
  private func importProgram(_ data: Data?) {
    switch WorkoutTemplateStore.check(data) {
    case .confirm(let templates): (pending, importMessage) = (templates, nil)
    case .refused(let line): importMessage = line
    }
  }

  private func replaceProgram(with templates: [WorkoutTemplate]) {
    let store = WorkoutTemplateStore(storage: environment.storage)
    var updated = library ?? store.load()
    importMessage = store.replaceProgram(with: templates, in: &updated)
    library = updated
  }

  /// Closes the logger at once, then writes the session to Health and keeps it either way.
  /// A session with no sets is discarded.
  private func finish(_ session: WorkoutSession) {
    (active, resuming) = (nil, nil)
    WorkoutSessionStore(storage: environment.storage).clear()
    keep(session, endedAt: Date())
  }

  /// The saved workout in progress: offered as Resume, or, idle too long, finished at its last
  /// set (an idle one with no sets is dropped). Runs when the Workout screen loads.
  private func loadSaved() {
    let store = WorkoutSessionStore(storage: environment.storage)
    let outcome = SessionResume.atLaunch(store.load(), now: Date())
    if case .resume(let logger) = outcome {
      resumable = logger
      return
    }
    store.clear()
    if case .close(let session, let end) = outcome { keep(session, endedAt: end) }
  }

  /// Opens the logger on a new session. A workout still offered as Resume is finished at its
  /// last set first, so the new session never overwrites it.
  private func start(_ template: WorkoutTemplate) {
    if let old = resumable, let end = SessionResume.lastSet(of: old.session) {
      keep(old.session, endedAt: end)
    }
    if resumable != nil { WorkoutSessionStore(storage: environment.storage).clear() }
    (resumable, resuming, active) = (nil, nil, template)
  }

  /// Saves the session on the phone, queues its record, then copies it to Health (D-076); the
  /// row shows once Health answered. A session with no sets is dropped.
  private func keep(_ session: WorkoutSession, endedAt end: Date) {
    guard let done = WorkoutFinish.close(session, at: end) else { return }
    let store = FinishedWorkoutStore(storage: environment.storage)
    let saved = (finished ?? store.load()) + [done]
    store.save(saved)
    Task {
      await environment.syncWorkout(done)
      var copied = done
      copied.inHealth = await WorkoutFinish.write(done, to: environment.healthStore)
      let updated = Array(saved.dropLast()) + [copied]
      finished = updated
      store.save(updated)
      environment.syncHermesInBackground()
    }
  }

  @ViewBuilder
  private var today: some View {
    // No session history is stored yet, so the rotation starts at the first template.
    let next = library?.next(after: nil)
    let others =
      (library?.days ?? []).filter { resumable != nil || $0.key != next?.key }
      + [Self.emptyWorkout]
    let week = WorkoutFinish.week(containing: Date(), in: finished ?? [])
    VStack(alignment: .leading, spacing: 12) {
      if let resumable {
        resumeCard(resumable)
      } else if let next {
        nextCard(next)
      }
      HStack(spacing: 12) {
        stat("Sessions this week", week.isEmpty ? nil : week.count, id: "workout.week.sessions")
        stat(
          "Working sets", week.isEmpty ? nil : week.reduce(0) { $0 + $1.workingSets },
          id: "workout.week.sets")
      }
      Button {
        showHistory = true
      } label: {
        Text("History")
          .font(.system(size: Theme.subtitleSize))
          .foregroundStyle(Theme.text)
          .padding(16)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(card(inverted: false))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("workout.history")
      ForEach(Array(week.enumerated()), id: \.offset) { index, workout in
        sessionRow(workout, id: "workout.session.\(index)")
      }
      ForEach(others, id: \.key) { template in
        Button {
          start(template)
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
        start(template)
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

  /// The black card while a workout is in progress: its template, sets so far, and Resume.
  private func resumeCard(_ logger: SetLogger) -> some View {
    let sets = logger.session.exercises.reduce(0) { $0 + $1.sets.count }
    return VStack(alignment: .leading, spacing: 8) {
      Text(logger.template.name)
        .font(.system(size: 28, weight: .semibold))
        .accessibilityIdentifier("workout.resume.name")
      Text("\(sets) \(sets == 1 ? "set" : "sets") logged")
        .font(.system(size: Theme.subtitleSize))
        .accessibilityIdentifier("workout.resume.sets")
      Button {
        (resuming, active, resumable) = (logger, logger.template, nil)
      } label: {
        Text("Resume")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(Theme.text)
          .frame(maxWidth: .infinity, minHeight: 48)
          .background(Capsule().fill(Theme.invertedText))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("workout.resume")
    }
    .foregroundStyle(Theme.invertedText)
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(card(inverted: true))
  }

  /// A finished session this week: its template, sets, and whether Health has it.
  private func sessionRow(_ workout: FinishedWorkout, id: String) -> some View {
    let key = workout.session.templateKey
    let name = key.flatMap { library?.names[$0] } ?? "Workout"
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
