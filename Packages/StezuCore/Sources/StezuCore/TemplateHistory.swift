import Foundation

/// Last-session numbers that prefer the template being done: Day 1's bench comes from the last
/// Day 1 session even when a newer Day 2 session also had bench.
public enum TemplateHistory {
  /// The latest earlier session of `templateKey` that had the exercise; when no session of that
  /// template had it, the latest earlier session of any template. Nil when the exercise was never
  /// done before `date` (absent, not zero).
  public static func lastSession(
    of exercise: String,
    template templateKey: String?,
    before date: Date,
    in sessions: [WorkoutSession],
    config: WorkoutHistoryConfig = WorkoutHistoryConfig()
  ) -> LastSessionNumbers? {
    if let templateKey {
      let same = sessions.filter { $0.templateKey == templateKey }
      if let found = WorkoutHistory.lastSession(
        of: exercise, before: date, in: same, config: config)
      {
        return found
      }
    }
    return WorkoutHistory.lastSession(of: exercise, before: date, in: sessions, config: config)
  }

  /// Last-session numbers for each exercise of `template`, keyed by exercise name. Exercises
  /// never done before have no key.
  public static func lastSessions(
    for template: WorkoutTemplate,
    before date: Date,
    in sessions: [WorkoutSession],
    config: WorkoutHistoryConfig = WorkoutHistoryConfig()
  ) -> [String: LastSessionNumbers] {
    var result: [String: LastSessionNumbers] = [:]
    for exercise in template.exercises {
      result[exercise.name] = lastSession(
        of: exercise.name, template: template.key, before: date, in: sessions, config: config)
    }
    return result
  }
}

extension LastSessionNumbers {
  /// The last session's set at this 0-based position, or its last set when it had fewer.
  public func set(at index: Int) -> WorkoutSet? {
    sets.indices.contains(index) ? sets[index] : sets.last
  }

  /// "Last 60 x 8, 7d ago" for the set at this position; "BW" for a bodyweight set.
  public func summary(setAt index: Int) -> String {
    guard let set = set(at: index) else { return "Last --" }
    let weight = set.pounds.map { String(format: "%g", $0) } ?? "BW"
    let age = daysAgo == 0 ? "today" : "\(daysAgo)d ago"
    return "Last \(weight) x \(set.reps), \(age)"
  }
}
