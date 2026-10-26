import Foundation
import StezuCore
import UIKit

/// S-028: the sync engine; its state lives in sync-state.json, next to finished-workouts.json.
enum HermesSyncFile {
  static func engine(storage: StorageMode) -> HealthSync {
    let file = FinishedWorkoutStore(storage: storage).file?.deletingLastPathComponent()
      .appendingPathComponent("sync-state.json")
    let saved = file.flatMap { try? Data(contentsOf: $0) }
      .flatMap { try? JSONDecoder().decode(SyncState.self, from: $0) }
    return HealthSync(state: saved ?? SyncState()) { state in
      guard let file, let data = try? JSONEncoder().encode(state) else { return }
      try? FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: file, options: .atomic)
    }
  }

  /// "--" before the first sync, else its time, the server's sample count and any waiting batches.
  static func text(_ state: SyncState) -> String {
    var parts = [time(state.lastSyncAt)]
    if let samples = state.samplesTotal { parts.append("\(samples) samples") }
    if let records = state.recordsTotal {
      parts.append("\(records) record\(records == 1 ? "" : "s")")
    }
    if !state.pending.isEmpty { parts.append("\(state.pending.count) waiting") }
    return parts.joined(separator: ", ")
  }

  /// A sync time, or "--" before there is one (S-033's background row too).
  static func time(_ date: Date?) -> String {
    date?.formatted(date: .abbreviated, time: .shortened) ?? "--"
  }
}

extension AppEnvironment {
  /// One pass; Health once connected (S-020) or faked, and only while the phone is unlocked
  /// (S-033). Unconfigured or offline: the queue waits. Then the next background run is asked for.
  @discardableResult
  func syncHermes(background: Bool = false) async -> SyncState {
    let unlocked = await MainActor.run { UIApplication.shared.isProtectedDataAvailable }
    let connected = unlocked && (isUITest || healthConnection.isConnected)
    defer { scheduleBackgroundSync() }
    return await healthSync.run(
      health: connected ? healthStore : nil, transport: vmTransport, background: background)
  }

  /// Open, foreground and Finish, off the main actor. `-uitest` syncs only on Sync now.
  /// S-030: also queues the workouts stored before this build, once (`-uitest` too).
  func syncHermesInBackground() {
    Task.detached(priority: .utility) {
      await self.backfillWorkouts()
      if !self.isUITest { await self.syncHermes() }
    }
  }

  /// S-029: a logged or edited meal, or a tombstone when `meal` is nil, joins the sync queue
  /// (saved before this returns), then a pass runs off the main actor, under `-uitest` too.
  func syncMeal(_ meal: LoggedMeal?, id: UUID, edited: Bool = false) async {
    let record = meal.map { SyncRecord.meal($0, edited: edited, at: Date()) }
    await syncRecords([record ?? .deletedMeal(id, at: Date())])
  }

  /// Records join the sync queue (saved before this returns), then a pass runs in the background.
  func syncRecords(_ records: [SyncRecord]) async {
    await healthSync.enqueue(records)
    Task.detached(priority: .utility) { await self.syncHermes() }
  }

  /// S-030: a finished session, after Finish saved it on the phone.
  func syncWorkout(_ workout: FinishedWorkout) async {
    let (templates, keys) = workoutNames()
    let name = workout.session.templateKey.flatMap { templates[$0] }
    await syncRecords([.session(workout, templateName: name, keys: keys, at: Date())])
  }

  /// Template names by key, and exercise keys by name: the library (swaps, custom exercises)
  /// first, then the templates' own exercises, which win.
  func workoutNames() -> (templates: [String: String], exercises: [String: String]) {
    let templates = WorkoutTemplateStore(storage: storage).load().templates
    let pairs =
      ExerciseLibraryStore(storage: storage).load().exercises.map { ($0.name, $0.key) }
      + templates.flatMap { $0.exercises.map { ($0.name, $0.key) } }
    return (
      Dictionary(templates.map { ($0.key, $0.name) }, uniquingKeysWith: { a, _ in a }),
      Dictionary(pairs, uniquingKeysWith: { _, b in b })
    )
  }

  /// The first launch with S-030 queues every finished session and the open logger's sets.
  func backfillWorkouts() async {
    guard await healthSync.state.workoutsBackfilled != true else { return }
    let (templates, keys) = workoutNames()
    await healthSync.backfillWorkouts(
      WorkoutRecords.backfill(
        finished: FinishedWorkoutStore(storage: storage).load(),
        active: WorkoutSessionStore(storage: storage).load()?.session, templates: templates,
        keys: keys, at: Date()))
  }
}
