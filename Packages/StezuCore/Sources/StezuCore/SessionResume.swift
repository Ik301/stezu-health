import Foundation

/// Settings for picking up a saved workout. Every value is a default, not a personal number.
public struct SessionResumeConfig: Sendable {
  /// A saved session idle for longer than this closes itself instead of resuming.
  public var idleLimit: TimeInterval

  public init(idleLimit: TimeInterval = 3 * 60 * 60) {
    self.idleLimit = idleLimit
  }
}

/// What the app does with the workout saved in progress when it loads it again.
public enum SessionResume: Sendable, Equatable {
  /// Nothing to resume: no saved workout, or an idle one with no sets (discarded, like Finish).
  case nothing
  /// Offer Resume: the logger exactly as it was saved.
  case resume(SetLogger)
  /// Idle too long: finish the session, ending at its last set.
  case close(WorkoutSession, endedAt: Date)

  /// Idle time runs from the last logged set, or from the start when no set is logged.
  public static func atLaunch(
    _ saved: SetLogger?, now: Date, config: SessionResumeConfig = SessionResumeConfig()
  ) -> SessionResume {
    guard let saved else { return .nothing }
    let last = lastSet(of: saved.session)
    guard now.timeIntervalSince(last ?? saved.session.startedAt) > config.idleLimit else {
      return .resume(saved)
    }
    guard let last else { return .nothing }
    return .close(saved.session, endedAt: last)
  }

  /// When the session's latest set was logged; nil with no sets.
  public static func lastSet(of session: WorkoutSession) -> Date? {
    session.exercises.flatMap(\.sets).map(\.loggedAt).max()
  }
}
