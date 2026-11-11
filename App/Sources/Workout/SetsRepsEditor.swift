import StezuCore
import SwiftUI

/// Add exercise (D-157, D-158): the Exercises library, then Sets and reps for the pick, in one
/// sheet. Cancel goes back to the library; Add calls `add`.
struct AddExerciseFlow: View {
  let history: [WorkoutSession]
  let add: (LibraryExercise, SlotShape) -> Void
  @State private var picked: LibraryExercise?

  var body: some View {
    if let picked {
      SetsRepsEditor(title: picked.name, shape: .added, save: "Add") { shape in
        if let shape { add(picked, shape) } else { self.picked = nil }
      }
    } else {
      ExerciseLibraryView(history: history) { picked = $0 }
    }
  }
}

/// Sets and reps (D-158) of an added exercise, changed only by steppers: 1 to 10 sets, and reps
/// from and to (the same number at both ends is a fixed number). `done` gets the shape, or nil
/// for Cancel.
struct SetsRepsEditor: View {
  let title: String
  let save: String
  let done: (SlotShape?) -> Void
  @State private var shape: SlotShape

  init(title: String, shape: SlotShape, save: String, done: @escaping (SlotShape?) -> Void) {
    (self.title, self.save, self.done) = (title, save, done)
    _shape = State(initialValue: shape)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spaceLg) {
      TopBar(
        title: title, titleID: "workout.shape.title",
        action: .init(title: "Cancel", id: "workout.shape.cancel") { done(nil) })
      Text(shape.summary).textStyle(.title2).accessibilityIdentifier("workout.shape.summary")
      stepper(
        "Sets", shape.sets, id: "workout.shape.sets", down: shape.sets > 1,
        up: shape.sets < SlotShape.maxSets
      ) { shape.stepSets(up: $0) }
      stepper(
        "Reps from", shape.repsLow, id: "workout.shape.repsLow", down: shape.repsLow > 1,
        up: shape.repsLow < SetLogger.maxReps
      ) { shape.stepRepsLow(up: $0) }
      stepper(
        "Reps to", shape.repsHigh, id: "workout.shape.repsHigh", down: shape.repsHigh > 1,
        up: shape.repsHigh < SetLogger.maxReps
      ) { shape.stepRepsHigh(up: $0) }
      Text("The same number at both ends is a fixed number of reps.")
        .textStyle(.label).foregroundStyle(Theme.muted)
      Button {
        done(shape)
      } label: {
        Text(save).textStyle(.headline).foregroundStyle(Theme.onInvert)
          .frame(maxWidth: .infinity, minHeight: Theme.sizeControl)
          .background(Theme.invert, in: Capsule())
      }
      .buttonStyle(.plain).accessibilityIdentifier("workout.shape.save")
    }
    .padding(Theme.spaceCard).foregroundStyle(Theme.ink)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(Theme.ground.ignoresSafeArea())
    .presentationDragIndicator(.visible)
  }

  /// A label, then the number between - and + buttons with ids "<id>.minus" and "<id>.plus".
  private func stepper(
    _ label: String, _ value: Int, id: String, down: Bool, up: Bool,
    step: @escaping (Bool) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: Theme.spaceXs) {
      Text(label).textStyle(.label).foregroundStyle(Theme.muted)
      HStack {
        ForEach([false, true], id: \.self) { isUp in
          let enabled = isUp ? up : down
          Button(isUp ? "+" : "-") { step(isUp) }
            .textStyle(.title2).frame(width: Theme.sizeControl, height: Theme.sizeControl)
            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1))
            .disabled(!enabled).opacity(enabled ? 1 : 0.4)
            .accessibilityIdentifier("\(id).\(isUp ? "plus" : "minus")")
          if !isUp {
            Text("\(value)").textStyle(.stat).frame(maxWidth: .infinity)
              .accessibilityIdentifier(id)
          }
        }
      }
      .buttonStyle(.plain)
    }
  }
}
