import Foundation

/// What a session did, next to the last session of its template: history, never advice (D-032).
/// It keeps the logger as it was at Finish, so Undo hands back the same session (D-113).
public struct WorkoutSummary: Sendable, Equatable {
  /// How long Undo stays on the summary after Finish.
  public static let undoWindow: TimeInterval = 8

  /// One exercise's sets and how its best set compares with last time's best.
  public struct ExerciseResult: Sendable, Equatable {
    public let exercise: String
    public let sets: [WorkoutSet]
    /// "+5 lb", "same", "-1 rep"; nil with nothing to compare (absent, not "same").
    public let change: String?
  }

  public let done: FinishedWorkout
  /// The logger at Finish; Undo returns it.
  public let logger: SetLogger
  public let exercises: [ExerciseResult]
  /// When the last earlier session of the template started; nil when there is none.
  public let lastSessionAt: Date?

  /// Nil for a session with no sets, which Finish discards.
  public init?(logger: SetLogger, endedAt: Date, history: [WorkoutSession]) {
    guard let done = WorkoutFinish.close(logger.session, at: endedAt) else { return nil }
    let start = done.session.startedAt
    let key = done.session.templateKey
    let same = history.filter {
      key != nil && key != WorkoutRotation.emptyKey && $0.templateKey == key
        && $0.startedAt < start
    }
    (self.done, self.logger) = (done, logger)
    lastSessionAt = same.map(\.startedAt).max()
    exercises = done.session.exercises.compactMap { log in
      guard let best = Self.best(log.sets) else { return nil }
      let earlier = WorkoutHistory.lastSession(of: log.exercise, before: start, in: same)
      return ExerciseResult(
        exercise: log.exercise, sets: log.sets,
        change: earlier.flatMap { Self.best($0.sets) }.flatMap { Self.change(best, from: $0) })
    }
  }

  /// Pounds x reps over the weighted sets; nil when every set was bodyweight (absent, not 0).
  public static func volume(_ session: WorkoutSession) -> Double? {
    let weighted = session.exercises.flatMap(\.sets).compactMap { set in
      set.pounds.map { $0 * Double(set.reps) }
    }
    return weighted.isEmpty ? nil : weighted.reduce(0, +)
  }

  /// The heaviest set, most reps among equals; a bodyweight set only when all were.
  public static func best(_ sets: [WorkoutSet]) -> WorkoutSet? {
    sets.max { ($0.pounds ?? -1, $0.reps) < ($1.pounds ?? -1, $1.reps) }
  }

  /// A different weight says pounds; the same weight (or bodyweight both times) says reps.
  public static func change(_ now: WorkoutSet, from last: WorkoutSet) -> String? {
    switch (now.pounds, last.pounds) {
    case (let new?, let old?) where new != old:
      return (new > old ? "+" : "-") + String(format: "%g lb", abs(new - old))
    case (nil, nil), (.some, .some):
      let reps = now.reps - last.reps
      guard reps != 0 else { return "same" }
      return (reps > 0 ? "+" : "-") + "\(abs(reps)) \(abs(reps) == 1 ? "rep" : "reps")"
    default:
      return nil
    }
  }

  /// The logger as it was at Finish while Undo is still offered; nil after the window.
  public func undo(at date: Date) -> SetLogger? {
    date.timeIntervalSince(done.endedAt) < Self.undoWindow ? logger : nil
  }

  /// Calendar days from one date to another: 0 the same day.
  public static func days(from date: Date, to now: Date, calendar: Calendar = .current) -> Int {
    calendar.dateComponents(
      [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
    ).day ?? 0
  }
}
