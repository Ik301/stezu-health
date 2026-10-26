import Foundation

/// A finished session as kept on the phone, and whether Apple Health has it.
public struct FinishedWorkout: Sendable, Equatable, Codable {
  public let session: WorkoutSession
  public let endedAt: Date
  /// The workout's external id in Health; the same session always gets the same id.
  public let externalID: String
  /// True once Health took the workout; false when the write was denied or failed.
  public var inHealth: Bool

  public init(session: WorkoutSession, endedAt: Date, externalID: String, inHealth: Bool) {
    self.session = session
    self.endedAt = endedAt
    self.externalID = externalID
    self.inHealth = inHealth
  }

  /// Every logged set counts as a working set (there are no warm-up sets yet).
  public var workingSets: Int { session.exercises.reduce(0) { $0 + $1.sets.count } }
}

public enum WorkoutFinish {
  /// Derived from the start time only, so finishing or retrying the same session repeats it.
  public static func externalID(for session: WorkoutSession) -> String {
    "stezu.workout.\(Int64((session.startedAt.timeIntervalSince1970 * 1000).rounded()))"
  }

  /// Ends the session at `date` and writes it to Health. A session with no sets is discarded:
  /// nil, and nothing is written. A denied or failed write still returns the session, with
  /// `inHealth` false.
  public static func finish(
    _ session: WorkoutSession, at date: Date, health: any HealthStore
  ) async -> FinishedWorkout? {
    guard session.exercises.contains(where: { !$0.sets.isEmpty }) else { return nil }
    let end = max(date, session.startedAt)
    let id = externalID(for: session)
    var inHealth = true
    do {
      try await health.saveStrengthWorkout(start: session.startedAt, end: end, externalID: id)
    } catch {
      inHealth = false
    }
    return FinishedWorkout(session: session, endedAt: end, externalID: id, inHealth: inHealth)
  }

  /// The finished sessions in the Monday-to-Sunday week holding `date`, newest first.
  public static func week(
    containing date: Date, in finished: [FinishedWorkout], calendar: Calendar = .current
  ) -> [FinishedWorkout] {
    var calendar = calendar
    calendar.firstWeekday = 2
    guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
    return finished.filter { week.contains($0.session.startedAt) }
      .sorted { $0.session.startedAt > $1.session.startedAt }
  }
}
