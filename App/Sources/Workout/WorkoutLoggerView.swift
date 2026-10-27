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
  /// The program's add-on blocks (S-035), each offered once as "+ <name>".
  private let addOns: [WorkoutTemplate]

  /// Finish (S-008): hands the session to the Workout screen, which closes the logger.
  private let onFinish: (WorkoutSession) -> Void

  /// `resuming` (S-009) reopens a saved logger as it was; otherwise a new session starts now.
  init(
    template: WorkoutTemplate, resuming: SetLogger? = nil, history: [WorkoutSession] = [],
    addOns: [WorkoutTemplate] = [], onFinish: @escaping (WorkoutSession) -> Void = { _ in }
  ) {
    (self.history, self.addOns) = (history, addOns)
    _logger = State(
      initialValue: resuming
        ?? SetLogger(template: template, startedAt: Date(), history: history))
    self.onFinish = onFinish
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.spaceMd) {
        HStack {
          Spacer()
          // No confirmation: one tap ends the rest and finishes.
          Button("Finish") {
            rest?.skip()
            onFinish(logger.session)
          }
          .textStyle(.headline)
          .foregroundStyle(Theme.ink)
          .frame(minWidth: 72, minHeight: Theme.sizeTarget)
          .accessibilityIdentifier("workout.logger.finish")
        }
        logCard
        restCard
        ForEach(Array(logger.loggedSets.enumerated()), id: \.offset) { index, set in
          Text(
            "Set \(index + 1)   \(Self.weight(set.pounds)) x \(set.reps)"
              + (logger.lastNumbers.map { "   " + $0.summary(setAt: index) } ?? "")
          )
          .textStyle(.subtitle)
          .foregroundStyle(Theme.ink)
          .padding(Theme.spaceLg)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.surface))
          .accessibilityIdentifier("workout.logger.logged.\(index)")
        }
        Button("Undo") { undo() }
          .textStyle(.headline)
          .foregroundStyle(Theme.ink)
          .disabled(!logger.canUndo)
          .opacity(logger.canUndo ? 1 : 0.4)
          .accessibilityIdentifier("workout.logger.undo")
        // One tap appends the block to this workout; the button goes once it is added.
        ForEach(addable, id: \.key) { addOn in
          Button("+ \(addOn.name)") { logger.append(addOn, history: history) }
            .textStyle(.subtitle, weight: .semibold)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: Theme.sizeControl)
            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 1))
            .buttonStyle(.plain)
            .accessibilityIdentifier("workout.logger.addon.\(addOn.key)")
        }
      }
    }
    .scrollIndicators(.hidden)
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

  /// The add-ons not yet appended to this workout.
  private var addable: [WorkoutTemplate] {
    addOns.filter { addOn in !logger.addOns.contains { $0.key == addOn.key } }
  }

  private var logCard: some View {
    VStack(alignment: .leading, spacing: Theme.spaceSm) {
      let exercise = logger.exercise
      HStack(alignment: .firstTextBaseline) {
        Text(exercise?.name ?? "No exercises")
          .textStyle(.title2)
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
        .textStyle(.subtitle)
        .accessibilityIdentifier("workout.logger.set")
      Text(exercise.map { "\($0.repRange) reps" } ?? "--")
        .textStyle(.label)
        .foregroundStyle(Theme.onInvertMuted)
        .accessibilityIdentifier("workout.logger.reps")
      // Last session's numbers for this set, same template first; "Last --" the first time.
      Text(
        exercise == nil
          ? "--" : logger.lastNumbers?.summary(setAt: logger.setNumber - 1) ?? "Last --"
      )
      .textStyle(.label)
      .foregroundStyle(Theme.onInvertMuted)
      .accessibilityIdentifier("workout.logger.last")
      stepper(
        logger.isBodyweight ? "BW" : logger.pounds.map { Self.weight($0) } ?? "--",
        id: "workout.logger.weight",
        enabled: !logger.isBodyweight
      ) { logger.stepWeight(up: $0) }
      stepper(exercise == nil ? "--" : "\(logger.reps)", id: "workout.logger.repCount") {
        logger.stepReps(up: $0)
      }
      HStack(spacing: Theme.spaceMd) {
        Button(logger.isBodyweight ? "Weight" : "BW") { logger.toggleBodyweight() }
          .textStyle(.headline)
          .frame(minWidth: 72, minHeight: Theme.sizeControl)
          .overlay(Capsule().strokeBorder(Theme.onInvert, lineWidth: 1))
          .accessibilityIdentifier("workout.logger.bodyweight")
        Button {
          logSet()
        } label: {
          Text("Log")
            .textStyle(.headline)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: Theme.sizeControl)
            .background(Capsule().fill(Theme.onInvert))
        }
        .disabled(!logger.canLog)
        .opacity(logger.canLog ? 1 : 0.4)
        .accessibilityIdentifier("workout.logger.log")
      }
    }
    .buttonStyle(.plain)
    .foregroundStyle(Theme.onInvert)
    .padding(Theme.spaceCard)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.invert))
  }

  /// Logs the card's set and starts the rest at that exercise's template rest, with no tap.
  private func logSet() {
    guard let exercise = logger.exercise else { return }
    let setLabel = "Set \(logger.setNumber) of \(exercise.sets)"
    guard let set = logger.log(at: Date()) else { return }
    saveThenSync(
      .set(set, exercise: exercise.name, key: exercise.key, in: logger.session, at: Date()))
    var controller = rest ?? RestActivityController(alerts: environment.restAlerts)
    controller.setLogged(exercise, setLabel: setLabel)
    rest = controller
  }

  /// Takes back the last set; the server gets the same set id as deleted (S-030).
  private func undo() {
    guard let set = logger.undo() else { return }
    saveThenSync(.deletedSet(set, in: logger.session, at: Date()))
  }

  /// The phone first (D-076): the logger is saved, then the record joins the sync queue.
  private func saveThenSync(_ record: SyncRecord) {
    WorkoutSessionStore(storage: environment.storage).save(logger)
    Task { await environment.syncRecords([record]) }
  }

  /// The countdown with -15 s, +15 s and Skip, while a rest runs. The countdown's value is the
  /// rest's start time, so a test can see that adjusting keeps it.
  @ViewBuilder
  private var restCard: some View {
    if let rest, let startedAt = rest.startedAt {
      VStack(alignment: .leading, spacing: Theme.spaceSm) {
        Text("Rest")
          .textStyle(.label)
          .foregroundStyle(Theme.muted)
        TimelineView(.periodic(from: startedAt, by: 1)) { _ in
          Text(RestActivityController.text(rest.remaining))
            .textStyle(.big)
            .foregroundStyle(Theme.ink)
            .accessibilityIdentifier("workout.rest.countdown")
            .accessibilityValue("\(Int(startedAt.timeIntervalSince1970))")
        }
        HStack(spacing: Theme.spaceMd) {
          restButton("-15 s", id: "workout.rest.minus") { self.rest?.adjust(by: -15) }
          restButton("+15 s", id: "workout.rest.plus") { self.rest?.adjust(by: 15) }
          restButton("Skip", id: "workout.rest.skip") { self.rest?.skip() }
        }
      }
      .padding(Theme.spaceLg)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.surface))
      .task(id: rest.endsAt) {
        guard let endsAt = self.rest?.endsAt else { return }
        try? await Task.sleep(for: .seconds(max(0, endsAt.timeIntervalSinceNow)))
        if !Task.isCancelled { self.rest?.tick() }
      }
    }
  }

  private func restButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
      .textStyle(.headline)
      .foregroundStyle(Theme.ink)
      .frame(maxWidth: .infinity, minHeight: Theme.sizeControl)
      .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 1))
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
        .textStyle(.big)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(id)
      stepButton(up: true, id: id, enabled: enabled, step: step)
    }
  }

  private func stepButton(
    up: Bool, id: String, enabled: Bool, step: @escaping (Bool) -> Void
  ) -> some View {
    Button(up ? "+" : "-") { step(up) }
      .textStyle(.title2)
      .frame(width: 48, height: 48)
      .overlay(Circle().strokeBorder(Theme.onInvert, lineWidth: 1))
      .disabled(!enabled)
      .opacity(enabled ? 1 : 0.4)
      .accessibilityIdentifier("\(id).\(up ? "plus" : "minus")")
  }

  /// A logged set's weight: "45 lb", "47.5 lb", or "BW" for a bodyweight set (nil pounds).
  static func weight(_ pounds: Double?) -> String {
    pounds.map { String(format: "%g lb", $0) } ?? "BW"
  }
}
