import StezuCore
import SwiftUI

/// S-055: one set of a finished session, picked in History or the Day view; `number` from 1.
struct PastSet: Identifiable {
  let sessionStart: Date
  let exercise: String
  let number: Int
  let set: WorkoutSet
  var id: Date { self.set.loggedAt }
}

/// An exercise's sets as chips, "60 x 8" (ids "<id>.<set index>"); a tap picks one.
struct SetChips: View {
  let sets: [WorkoutSet]
  let id: String
  let pick: (Int) -> Void

  var body: some View {
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 76), spacing: Theme.spaceSm)], alignment: .leading,
      spacing: Theme.spaceSm
    ) {
      ForEach(Array(sets.enumerated()), id: \.offset) { index, set in
        Button(action: { pick(index) }) {
          Text(WorkoutHistoryView.sets([set])).textStyle(.subtitle)
            .frame(maxWidth: .infinity, minHeight: Theme.sizeTarget)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.radiusChip))
        }
        .buttonStyle(.plain).foregroundStyle(Theme.ink)
        .accessibilityIdentifier("\(id).\(index)")
      }
    }
  }
}

/// A past set's weight and reps (5 lb steps; a bodyweight set stays BW) with Save, and Delete,
/// which turns into Confirm first. `done` gets the edit, or nil for Cancel.
struct SetEditor: View {
  let past: PastSet
  let done: (SetEdit?) -> Void
  @State private var pounds: Double?
  @State private var reps: Int
  @State private var confirming = false

  init(past: PastSet, done: @escaping (SetEdit?) -> Void) {
    (self.past, self.done) = (past, done)
    (_pounds, _reps) = (State(initialValue: past.set.pounds), State(initialValue: past.set.reps))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spaceLg) {
      TopBar(
        title: "\(past.exercise), set \(past.number)", titleID: "set.edit.title",
        action: .init(title: "Cancel", id: "set.edit.cancel") { done(nil) })
      stepper(WorkoutLoggerView.weight(pounds), id: "set.edit.weight", enabled: pounds != nil) {
        up in
        pounds = pounds.map { up ? min($0 + 5, SetLogger.maxPounds) : $0 > 5 ? $0 - 5 : $0 }
      }
      stepper("\(reps)", id: "set.edit.reps", enabled: true) { up in
        reps = min(max(reps + (up ? 1 : -1), 1), SetLogger.maxReps)
      }
      pill("Save", id: "set.edit.save", filled: true) {
        done(.change(pounds: pounds, reps: reps))
      }
      pill(confirming ? "Confirm" : "Delete", id: "set.edit.delete", filled: false) {
        if confirming { done(.delete) } else { confirming = true }
      }
    }
    .padding(Theme.spaceCard).foregroundStyle(Theme.ink)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(Theme.ground.ignoresSafeArea())
  }

  private func stepper(
    _ value: String, id: String, enabled: Bool, step: @escaping (Bool) -> Void
  ) -> some View {
    HStack {
      ForEach([false, true], id: \.self) { up in
        Button(up ? "+" : "-") { step(up) }
          .textStyle(.title2).frame(width: Theme.sizeControl, height: Theme.sizeControl)
          .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1))
          .disabled(!enabled).opacity(enabled ? 1 : 0.4)
          .accessibilityIdentifier("\(id).\(up ? "plus" : "minus")")
        if !up {
          Text(value).textStyle(.big).frame(maxWidth: .infinity).accessibilityIdentifier(id)
        }
      }
    }
    .buttonStyle(.plain)
  }

  private func pill(_ title: String, id: String, filled: Bool, run: @escaping () -> Void)
    -> some View
  {
    Button(action: run) {
      Text(title).textStyle(.headline).foregroundStyle(filled ? Theme.onInvert : Theme.ink)
        .frame(maxWidth: .infinity, minHeight: Theme.sizeControl)
        .background(filled ? Theme.invert : Theme.surfaceRaised, in: Capsule())
    }
    .buttonStyle(.plain).accessibilityIdentifier(id)
  }
}

extension AppEnvironment {
  /// S-055: the edit on the phone first (finished-workouts.json), then the set (or its tombstone)
  /// and the session join the sync queue again; Health is left alone (D-139).
  func editSet(_ edit: SetEdit, _ past: PastSet, in workouts: [FinishedWorkout]) async
    -> [FinishedWorkout]
  {
    let (templates, keys) = workoutNames()
    guard let index = workouts.firstIndex(where: { $0.session.startedAt == past.sessionStart }),
      let result = workouts[index].applying(
        edit, toSetAt: past.set.loggedAt,
        templateName: workouts[index].session.templateKey.flatMap { templates[$0] }, keys: keys,
        at: Date())
    else { return workouts }
    var saved = workouts
    saved[index] = result.workout
    FinishedWorkoutStore(storage: storage).save(saved)
    await syncRecords(result.records)
    return saved
  }
}
