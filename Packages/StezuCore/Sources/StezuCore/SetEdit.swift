import Foundation

/// S-055: a change to one set of a finished session, made after the fact.
public enum SetEdit: Sendable, Equatable {
  /// New numbers; nil pounds is a bodyweight set.
  case change(pounds: Double?, reps: Int)
  case delete
}

extension FinishedWorkout {
  /// The workout after the edit and the records to queue (D-139): the set again under its id
  /// (or its tombstone, as Undo sends), then the session again under its id, both stamped
  /// `date`. A session left with no sets is kept. Nil when nothing changed.
  public func applying(
    _ edit: SetEdit, toSetAt loggedAt: Date, templateName: String?, keys: [String: String],
    at date: Date
  ) -> (workout: FinishedWorkout, records: [SyncRecord])? {
    var edited = session
    guard let old = session.exercises.flatMap(\.sets).first(where: { $0.loggedAt == loggedAt }),
      let exercise = edited.apply(edit, toSetAt: loggedAt)
    else { return nil }
    let done = FinishedWorkout(
      session: edited, endedAt: endedAt, externalID: externalID, inHealth: inHealth)
    let set: SyncRecord
    switch edit {
    case .change(let pounds, let reps):
      set = .set(
        WorkoutSet(pounds: pounds, reps: reps, loggedAt: loggedAt), exercise: exercise,
        key: keys[exercise], in: edited, at: date)
    case .delete:
      set = .deletedSet(old, in: edited, at: date)
    }
    return (done, [set, .session(done, templateName: templateName, keys: keys, at: date)])
  }
}
