import StezuCore
import SwiftUI

/// The logger: the black Log card holds the set being prepared, prefilled and changed only by
/// steppers (no keyboard), and Log records it in one tap. Logged sets of the exercise are listed
/// below with Undo. Every change is saved to the session store at once.
struct WorkoutLoggerView: View {
  @Environment(\.appEnvironment) private var environment
  @State private var logger: SetLogger
  /// The rest after the last logged set (S-006); nil until the first Log.
  @State private var rest: RestActivityController?
  @State private var showLibrary = false  // the Exercises library sheet (S-007)
  private let history: [WorkoutSession]

  /// Finish (S-008): hands the session to the Workout screen, which closes the logger.
  private let onFinish: (WorkoutSession) -> Void

  /// `resuming` (S-009) reopens a saved logger as it was; otherwise a new session starts now.
  init(
    template: WorkoutTemplate, resuming: SetLogger? = nil, history: [WorkoutSession] = [],
    onFinish: @escaping (WorkoutSession) -> Void = { _ in }
  ) {
    self.history = history
    _logger = State(
      initialValue: resuming
        ?? SetLogger(template: template, startedAt: Date(), history: history))
    self.onFinish = onFinish
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Spacer()
          // No confirmation: one tap ends the rest and finishes.
          Button("Finish") {
            rest?.skip()
            onFinish(logger.session)
          }
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(Theme.text)
          .frame(minWidth: 72, minHeight: 44)
          .accessibilityIdentifier("workout.logger.finish")
        }
        logCard
        restCard
        ForEach(Array(logger.loggedSets.enumerated()), id: \.offset) { index, set in
          Text(
            "Set \(index + 1)   \(Self.weight(set.pounds)) x \(set.reps)"
              + (logger.lastNumbers.map { "   " + $0.summary(setAt: index) } ?? "")
          )
          .font(.system(size: Theme.subtitleSize))
          .foregroundStyle(Theme.text)
          .padding(16)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.card))
          .accessibilityIdentifier("workout.logger.logged.\(index)")
        }
        Button("Undo") { logger.undo() }
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(Theme.text)
          .disabled(!logger.canUndo)
          .opacity(logger.canUndo ? 1 : 0.4)
          .accessibilityIdentifier("workout.logger.undo")
      }
    }
    .onChange(of: logger) { _, changed in
      WorkoutSessionStore(storage: environment.storage).save(changed)
    }
    .sheet(isPresented: $showLibrary) {
      ExerciseLibraryView(history: history + [logger.session]) { picked in
        logger.swap(to: picked, history: history)
        showLibrary = false
      }
      .environment(\.appEnvironment, environment)
    }
  }

  private var logCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      let exercise = logger.exercise
      HStack(alignment: .firstTextBaseline) {
        Text(exercise?.name ?? "No exercises")
          .font(.system(size: 28, weight: .semibold))
          .accessibilityIdentifier("workout.logger.exercise")
        Spacer()
        if exercise != nil {
          Menu {
            Button("Swap") { showLibrary = true }
              .accessibilityIdentifier("workout.logger.swap")
          } label: {
            Image(systemName: "ellipsis").frame(width: 48, height: 48)
          }
          .accessibilityIdentifier("workout.logger.menu")
        }
      }
      Text(exercise.map { "Set \(logger.setNumber) of \($0.sets)" } ?? "--")
        .font(.system(size: Theme.subtitleSize))
        .accessibilityIdentifier("workout.logger.set")
      Text(exercise.map { "\($0.repRange) reps" } ?? "--")
        .font(.system(size: Theme.labelSize))
        .foregroundStyle(Theme.label)
        .accessibilityIdentifier("workout.logger.reps")
      // Last session's numbers for this set, same template first; "Last --" the first time.
      Text(
        exercise == nil
          ? "--" : logger.lastNumbers?.summary(setAt: logger.setNumber - 1) ?? "Last --"
      )
      .font(.system(size: Theme.labelSize))
      .foregroundStyle(Theme.label)
      .accessibilityIdentifier("workout.logger.last")
      stepper(
        logger.isBodyweight ? "BW" : logger.pounds.map { Self.weight($0) } ?? "--",
        id: "workout.logger.weight",
        enabled: !logger.isBodyweight
      ) { logger.stepWeight(up: $0) }
      stepper(exercise == nil ? "--" : "\(logger.reps)", id: "workout.logger.repCount") {
        logger.stepReps(up: $0)
      }
      HStack(spacing: 12) {
        Button(logger.isBodyweight ? "Weight" : "BW") { logger.toggleBodyweight() }
          .font(.system(size: 17, weight: .semibold))
          .frame(minWidth: 72, minHeight: 48)
          .overlay(Capsule().strokeBorder(Theme.invertedText, lineWidth: 1))
          .accessibilityIdentifier("workout.logger.bodyweight")
        Button {
          logSet()
        } label: {
          Text("Log")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Capsule().fill(Theme.invertedText))
        }
        .disabled(!logger.canLog)
        .opacity(logger.canLog ? 1 : 0.4)
        .accessibilityIdentifier("workout.logger.log")
      }
    }
    .buttonStyle(.plain)
    .foregroundStyle(Theme.invertedText)
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.invertedCard))
  }

  /// Logs the card's set and starts the rest at that exercise's template rest, with no tap.
  private func logSet() {
    guard let exercise = logger.exercise else { return }
    let setLabel = "Set \(logger.setNumber) of \(exercise.sets)"
    guard logger.log(at: Date()) != nil else { return }
    var controller = rest ?? RestActivityController(alerts: environment.restAlerts)
    controller.setLogged(exercise, setLabel: setLabel)
    rest = controller
  }

  /// The countdown with -15 s, +15 s and Skip, while a rest runs. The countdown's value is the
  /// rest's start time, so a test can see that adjusting keeps it.
  @ViewBuilder
  private var restCard: some View {
    if let rest, let startedAt = rest.startedAt {
      VStack(alignment: .leading, spacing: 8) {
        Text("Rest")
          .font(.system(size: Theme.labelSize))
          .foregroundStyle(Theme.label)
        TimelineView(.periodic(from: startedAt, by: 1)) { _ in
          Text(RestActivityController.text(rest.remaining))
            .font(.system(size: Theme.bigNumberSize, weight: .medium).monospacedDigit())
            .tracking(Theme.bigNumberTracking)
            .foregroundStyle(Theme.text)
            .accessibilityIdentifier("workout.rest.countdown")
            .accessibilityValue("\(Int(startedAt.timeIntervalSince1970))")
        }
        HStack(spacing: 12) {
          restButton("-15 s", id: "workout.rest.minus") { self.rest?.adjust(by: -15) }
          restButton("+15 s", id: "workout.rest.plus") { self.rest?.adjust(by: 15) }
          restButton("Skip", id: "workout.rest.skip") { self.rest?.skip() }
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.card))
      .task(id: rest.endsAt) {
        guard let endsAt = self.rest?.endsAt else { return }
        try? await Task.sleep(for: .seconds(max(0, endsAt.timeIntervalSinceNow)))
        if !Task.isCancelled { self.rest?.tick() }
      }
    }
  }

  private func restButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
      .font(.system(size: 17, weight: .semibold))
      .foregroundStyle(Theme.text)
      .frame(maxWidth: .infinity, minHeight: 48)
      .overlay(Capsule().strokeBorder(Theme.text, lineWidth: 1))
      .buttonStyle(.plain)
      .accessibilityIdentifier(id)
  }

  /// A big number between - and + buttons with ids "<id>.minus" and "<id>.plus".
  private func stepper(
    _ value: String, id: String, enabled: Bool = true, step: @escaping (Bool) -> Void
  ) -> some View {
    HStack {
      stepButton(up: false, id: id, enabled: enabled, step: step)
      Text(value)
        .font(.system(size: Theme.bigNumberSize, weight: .medium))
        .tracking(Theme.bigNumberTracking)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(id)
      stepButton(up: true, id: id, enabled: enabled, step: step)
    }
  }

  private func stepButton(
    up: Bool, id: String, enabled: Bool, step: @escaping (Bool) -> Void
  ) -> some View {
    Button(up ? "+" : "-") { step(up) }
      .font(.system(size: 24, weight: .semibold))
      .frame(width: 48, height: 48)
      .overlay(Circle().strokeBorder(Theme.invertedText, lineWidth: 1))
      .disabled(!enabled)
      .opacity(enabled ? 1 : 0.4)
      .accessibilityIdentifier("\(id).\(up ? "plus" : "minus")")
  }

  /// A logged set's weight: "45 lb", "47.5 lb", or "BW" for a bodyweight set (nil pounds).
  static func weight(_ pounds: Double?) -> String {
    pounds.map { String(format: "%g lb", $0) } ?? "BW"
  }
}
