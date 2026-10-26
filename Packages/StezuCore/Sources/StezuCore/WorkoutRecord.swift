import Foundation

/// A logged set as a `set` record's payload (S-030), and each set inside a session's payload.
/// Ids derive from the session's start and the set's time, so a backfill repeats them.
public struct SetRecord: Codable, Sendable, Equatable {
  public let id, sessionId: String
  public let templateKey, exerciseKey: String?
  public let exercise: String
  /// Nil (sent as null) for a bodyweight set, never 0.
  public let pounds: Double?
  public let reps: Int
  public let loggedAt, kind: String

  enum CodingKeys: String, CodingKey {
    case id, exercise, pounds, reps, kind
    case sessionId = "session_id"
    case templateKey = "template_key"
    case exerciseKey = "exercise_key"
    case loggedAt = "logged_at"
  }

  init(_ set: WorkoutSet, exercise: String, key: String?, in session: WorkoutSession) {
    (id, sessionId) = (
      WorkoutRecords.setID(set, in: session), WorkoutFinish.externalID(for: session)
    )
    (templateKey, exerciseKey, self.exercise) = (session.templateKey, key, exercise)
    (pounds, reps, kind) = (set.pounds, set.reps, "working")
    loggedAt = SyncRecord.stamp(set.loggedAt, .current)
  }

  /// Every key, absent ones as null, so a bodyweight set says `"pounds": null`.
  public func encode(to encoder: any Encoder) throws {
    var box = encoder.container(keyedBy: CodingKeys.self)
    try box.encode(id, forKey: .id)
    try box.encode(sessionId, forKey: .sessionId)
    try box.encode(exercise, forKey: .exercise)
    try box.encode(templateKey, forKey: .templateKey)
    try box.encode(exerciseKey, forKey: .exerciseKey)
    try box.encode(pounds, forKey: .pounds)
    try box.encode(reps, forKey: .reps)
    try box.encode(loggedAt, forKey: .loggedAt)
    try box.encode(kind, forKey: .kind)
  }
}

/// A finished session as a `workout_session` record's payload: what was actually done, swaps
/// and custom exercises included, each exercise with its key (nil when unknown) and name.
public struct SessionRecord: Codable, Sendable, Equatable {
  public struct Exercise: Codable, Sendable, Equatable {
    public let key: String?
    public let name: String
    public let sets: [SetRecord]
  }

  public let id: String
  public let templateKey, templateName: String?
  public let start, end: String
  public let exercises: [Exercise]

  enum CodingKeys: String, CodingKey {
    case id, start, end, exercises
    case templateKey = "template_key"
    case templateName = "template_name"
  }
}

public enum WorkoutRecords {
  /// The session's id (its Health external id) plus the set's time in milliseconds.
  public static func setID(_ set: WorkoutSet, in session: WorkoutSession) -> String {
    let millis = Int64((set.loggedAt.timeIntervalSince1970 * 1000).rounded())
    return "\(WorkoutFinish.externalID(for: session)).set.\(millis)"
  }

  /// Every finished session and each set of the workout in progress, for the one-time backfill
  /// (`HealthSync.backfillWorkouts`). `templates`: names by key; `keys`: exercise keys by name.
  public static func backfill(
    finished: [FinishedWorkout], active: WorkoutSession?, templates: [String: String],
    keys: [String: String], at date: Date
  ) -> [SyncRecord] {
    let sessions = finished.map {
      SyncRecord.session(
        $0, templateName: $0.session.templateKey.flatMap { templates[$0] }, keys: keys, at: date)
    }
    guard let active else { return sessions }
    return sessions
      + active.exercises.flatMap { log in
        log.sets.map {
          SyncRecord.set($0, exercise: log.exercise, key: keys[log.exercise], in: active, at: date)
        }
      }
  }
}

extension SyncRecord {
  /// A logged set, right after the phone saved it.
  public static func set(
    _ set: WorkoutSet, exercise: String, key: String?, in session: WorkoutSession, at date: Date
  ) -> SyncRecord {
    SyncRecord(
      kind: "set", id: WorkoutRecords.setID(set, in: session), updatedAt: stamp(date, .current),
      deleted: false, setPayload: SetRecord(set, exercise: exercise, key: key, in: session))
  }

  /// An undone set: the same id as a tombstone.
  public static func deletedSet(_ set: WorkoutSet, in session: WorkoutSession, at date: Date)
    -> SyncRecord
  {
    SyncRecord(
      kind: "set", id: WorkoutRecords.setID(set, in: session), updatedAt: stamp(date, .current),
      deleted: true)
  }

  /// A finished session with its exercises in logged order and their sets.
  public static func session(
    _ workout: FinishedWorkout, templateName: String?, keys: [String: String], at date: Date
  ) -> SyncRecord {
    let session = workout.session
    let exercises = session.exercises.map { log in
      let key = keys[log.exercise]
      return SessionRecord.Exercise(
        key: key, name: log.exercise,
        sets: log.sets.map { SetRecord($0, exercise: log.exercise, key: key, in: session) })
    }
    let payload = SessionRecord(
      id: workout.externalID, templateKey: session.templateKey, templateName: templateName,
      start: stamp(session.startedAt, .current), end: stamp(workout.endedAt, .current),
      exercises: exercises)
    return SyncRecord(
      kind: "workout_session", id: workout.externalID, updatedAt: stamp(date, .current),
      deleted: false, sessionPayload: payload)
  }
}
