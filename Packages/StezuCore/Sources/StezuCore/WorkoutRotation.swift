import Foundation

/// Which day comes next (D-089) and which finished session can still be continued (D-090).
/// Home and the Workout screen both ask here, so they always agree.
public enum WorkoutRotation {
  /// A finished session can be continued while it started less than this long ago.
  public static let continueWindow: TimeInterval = 12 * 3600
  /// The Empty workout's key: not a day, so it never moves the rotation.
  public static let emptyKey = "empty"

  /// The day after the template of the session that finished last (by end time), whether it
  /// was the planned day or one started off schedule. By order only, never by date. The first
  /// day when nothing was finished or that template is no longer in the program.
  public static func next(in library: TemplateLibrary, finished: [FinishedWorkout])
    -> WorkoutTemplate?
  {
    let last =
      finished
      .filter { ($0.session.templateKey ?? emptyKey) != emptyKey }
      .max { $0.endedAt < $1.endedAt }
    return library.next(after: last?.session.templateKey)
  }

  /// True while the session started under 12 hours before `now` and its template still exists.
  public static func canContinue(
    _ workout: FinishedWorkout, library: TemplateLibrary, now: Date
  ) -> Bool {
    let age = now.timeIntervalSince(workout.session.startedAt)
    return age >= 0 && age < continueWindow && template(of: workout, in: library) != nil
  }

  /// The newest session that can be continued, for the row under the black card.
  public static func continuable(
    _ finished: [FinishedWorkout], library: TemplateLibrary, now: Date
  ) -> FinishedWorkout? {
    finished.filter { canContinue($0, library: library, now: now) }
      .max { $0.endedAt < $1.endedAt }
  }

  /// The logger reopened on a finished session: the same session (so the same id) with its
  /// sets, and new sets append. Nil when its template is gone.
  public static func reopen(
    _ workout: FinishedWorkout, library: TemplateLibrary, history: [WorkoutSession]
  ) -> SetLogger? {
    template(of: workout, in: library).map {
      SetLogger(continuing: workout.session, template: $0, history: history)
    }
  }

  /// Finished sessions after a Finish: one with the same id is replaced in place (a continued
  /// session), otherwise the new one is appended.
  public static func keep(_ done: FinishedWorkout, in finished: [FinishedWorkout])
    -> [FinishedWorkout]
  {
    guard let index = finished.firstIndex(where: { $0.externalID == done.externalID }) else {
      return finished + [done]
    }
    var kept = finished
    kept[index] = done
    return kept
  }

  private static func template(of workout: FinishedWorkout, in library: TemplateLibrary)
    -> WorkoutTemplate?
  {
    guard let key = workout.session.templateKey, key != emptyKey else { return nil }
    return library.templates.first { $0.key == key }
  }
}
