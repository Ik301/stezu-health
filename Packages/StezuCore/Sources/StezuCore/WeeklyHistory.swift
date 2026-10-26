import Foundation

/// One Monday-to-Sunday week that has at least one session. A week without sessions has no
/// value at all, so it never shows as a row of zeros.
public struct HistoryWeek: Sendable, Equatable {
  /// Monday at the start of the day.
  public let start: Date
  /// Sunday, the week's last day, at the start of the day.
  public let end: Date
  /// The week's sessions, newest first.
  public let sessions: [WorkoutSession]

  /// Every logged set counts as a working set (there are no warm-up sets yet, as in S-008).
  public var workingSets: Int { sessions.reduce(0) { $0 + $1.workingSets } }
}

extension WorkoutSession {
  /// Every logged set of the session; see `HistoryWeek.workingSets`.
  public var workingSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }
}

public enum WeeklyHistory {
  /// Groups sessions into Monday-to-Sunday weeks, newest week first. Weeks are found from the
  /// sessions themselves, so only weeks with a session appear.
  public static func weeks(
    _ sessions: [WorkoutSession], calendar: Calendar = .current
  ) -> [HistoryWeek] {
    var calendar = calendar
    calendar.firstWeekday = 2
    var byStart: [Date: [WorkoutSession]] = [:]
    for session in sessions {
      guard let week = calendar.dateInterval(of: .weekOfYear, for: session.startedAt) else {
        continue
      }
      byStart[week.start, default: []].append(session)
    }
    return byStart.sorted { $0.key > $1.key }.map { start, sessions in
      HistoryWeek(
        start: start, end: calendar.date(byAdding: .day, value: 6, to: start) ?? start,
        sessions: sessions.sorted { $0.startedAt > $1.startedAt })
    }
  }

  /// The sessions with at least one set of `exercise`, newest first.
  public static func sessions(
    with exercise: String, in sessions: [WorkoutSession]
  ) -> [WorkoutSession] {
    sessions.filter { !($0.sets(for: exercise) ?? []).isEmpty }
      .sorted { $0.startedAt > $1.startedAt }
  }
}
