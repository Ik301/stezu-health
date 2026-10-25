import Foundation

/// One logged set. Weight is in pounds; nil means no external load (a bodyweight set), not zero.
public struct WorkoutSet: Sendable, Equatable, Codable {
  public let pounds: Double?
  public let reps: Int
  public let loggedAt: Date

  public init(pounds: Double?, reps: Int, loggedAt: Date) {
    self.pounds = pounds
    self.reps = reps
    self.loggedAt = loggedAt
  }
}

/// The sets done for one exercise in one session, in the order they were logged.
public struct ExerciseLog: Sendable, Equatable, Codable {
  public let exercise: String
  public internal(set) var sets: [WorkoutSet]

  public init(exercise: String, sets: [WorkoutSet] = []) {
    self.exercise = exercise
    self.sets = sets
  }
}

/// One visit to the gym: exercises in the order they were first logged.
public struct WorkoutSession: Sendable, Equatable, Codable {
  public let startedAt: Date
  public private(set) var exercises: [ExerciseLog]

  public init(startedAt: Date, exercises: [ExerciseLog] = []) {
    self.startedAt = startedAt
    self.exercises = exercises
  }

  /// Logs one set in one call. The exercise is added on its first set.
  /// Returns nil and changes nothing when the set is not a real set:
  /// reps below 1, or a weight that is negative, zero or not finite (use nil for bodyweight).
  @discardableResult
  public mutating func logSet(
    _ exercise: String, pounds: Double?, reps: Int, at date: Date
  ) -> WorkoutSet? {
    guard reps >= 1 else { return nil }
    if let pounds, !(pounds.isFinite && pounds > 0) { return nil }
    let set = WorkoutSet(pounds: pounds, reps: reps, loggedAt: date)
    if let index = exercises.firstIndex(where: { $0.exercise == exercise }) {
      exercises[index].sets.append(set)
    } else {
      exercises.append(ExerciseLog(exercise: exercise, sets: [set]))
    }
    return set
  }

  /// Removes the last set of an exercise and returns it; drops the exercise when none is left.
  @discardableResult
  public mutating func removeLastSet(of exercise: String) -> WorkoutSet? {
    guard let index = exercises.firstIndex(where: { $0.exercise == exercise }),
      let set = exercises[index].sets.popLast()
    else { return nil }
    if exercises[index].sets.isEmpty { exercises.remove(at: index) }
    return set
  }

  /// The sets for an exercise in this session, or nil if it was not done.
  public func sets(for exercise: String) -> [WorkoutSet]? {
    exercises.first(where: { $0.exercise == exercise })?.sets
  }
}

/// The numbers from the most recent earlier session that included an exercise.
public struct LastSessionNumbers: Sendable, Equatable {
  public let exercise: String
  public let sessionStartedAt: Date
  public let sets: [WorkoutSet]
  public let daysAgo: Int
  /// How well these numbers describe the lifter today, which fades as they age.
  public let confidence: Confidence
}

/// Settings for last-session lookups. Every value is a default, not a personal number.
public struct WorkoutHistoryConfig: Sendable {
  public var calendar: Calendar
  /// High confidence while the last session is at most this many days old.
  public var highMaxDaysAgo: Int
  /// Medium up to this many days; anything older is low.
  public var mediumMaxDaysAgo: Int

  public init(calendar: Calendar = .current, highMaxDaysAgo: Int = 14, mediumMaxDaysAgo: Int = 42) {
    self.calendar = calendar
    self.highMaxDaysAgo = highMaxDaysAgo
    self.mediumMaxDaysAgo = mediumMaxDaysAgo
  }
}

public enum WorkoutHistory {
  /// The last session's numbers for an exercise: the latest session that started before `date`
  /// and has at least one set of it. Nil when there is no such session (absent, not zero).
  public static func lastSession(
    of exercise: String,
    before date: Date,
    in sessions: [WorkoutSession],
    config: WorkoutHistoryConfig = WorkoutHistoryConfig()
  ) -> LastSessionNumbers? {
    let match =
      sessions
      .filter { $0.startedAt < date }
      .compactMap { session -> (Date, [WorkoutSet])? in
        guard let sets = session.sets(for: exercise), !sets.isEmpty else { return nil }
        return (session.startedAt, sets)
      }
      .max(by: { $0.0 < $1.0 })
    guard let (startedAt, sets) = match else { return nil }

    let calendar = config.calendar
    let daysAgo =
      calendar.dateComponents(
        [.day], from: calendar.startOfDay(for: startedAt), to: calendar.startOfDay(for: date)
      ).day ?? 0
    let level: Confidence.Level =
      daysAgo <= config.highMaxDaysAgo
      ? .high : daysAgo <= config.mediumMaxDaysAgo ? .medium : .low
    let reason = "\(sets.count) \(sets.count == 1 ? "set" : "sets"), \(daysAgo) days ago"
    return LastSessionNumbers(
      exercise: exercise, sessionStartedAt: startedAt, sets: sets, daysAgo: daysAgo,
      confidence: Confidence(level: level, reason: reason))
  }

  /// Last-session numbers for every exercise in `sessions` done before `date`, keyed by name.
  /// Exercises never done before `date` have no key.
  public static func lastSessions(
    before date: Date,
    in sessions: [WorkoutSession],
    config: WorkoutHistoryConfig = WorkoutHistoryConfig()
  ) -> [String: LastSessionNumbers] {
    let names = Set(
      sessions.filter { $0.startedAt < date }.flatMap { $0.exercises.map(\.exercise) })
    var result: [String: LastSessionNumbers] = [:]
    for name in names {
      result[name] = lastSession(of: name, before: date, in: sessions, config: config)
    }
    return result
  }
}
