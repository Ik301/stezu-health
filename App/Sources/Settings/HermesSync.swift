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
  /// S-030, S-056: also queues the workouts and places stored before them, once (`-uitest` too).
  func syncHermesInBackground() {
    Task.detached(priority: .utility) {
      await self.backfillWorkouts()
      await self.myPlaces.backfill(into: self.healthSync)
      let library = WorkoutTemplateStore(storage: self.storage).load()  // S-057
      await self.healthSync.backfillProgram(
        library.programImported ? .program(library, at: Date()) : nil)
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

  /// S-057 (D-143): what GET /records/summary says the VM holds; nil when it cannot be read.
  func restoreSummary(via transport: (any VMTransport)? = nil) async -> RestoreSummary? {
    let reply = try? await (transport ?? vmTransport).send(VMRequest(path: "/records/summary"))
    return try? JSONDecoder().decode(RestoreSummary.self, from: reply?.body ?? Data())
  }

  /// S-058: the summary to offer a fresh install once, right after Save; nil otherwise.
  func restoreOffer(via transport: any VMTransport) async -> RestoreSummary? {
    let fresh = Restore.isFresh(
      finished: FinishedWorkoutStore(storage: storage).load(), meals: await mealCaptures.logged(),
      log: await places.log, library: WorkoutTemplateStore(storage: storage).load())
    guard fresh, let summary = await restoreSummary(via: transport), summary.hasRecords,
      await healthSync.offerRestore()
    else { return nil }
    return summary
  }

  /// Reads every page first, then writes the program, the finished workouts and the new meals,
  /// then (S-058) visits, fixes, weigh-ins and his places the phone lacks. Nothing is deleted or
  /// written to Health; only corrected session summaries are queued.
  func restoreFromHermes(via transport: (any VMTransport)? = nil) async throws -> String {
    let records = try await Restore.fetch(
      transport ?? vmTransport,
      kinds: "program,set,workout_session,meal,visit,location,weigh_in,my_place")
    let templates = WorkoutTemplateStore(storage: storage)
    let workouts = FinishedWorkoutStore(storage: storage)
    let outcome = Restore.merge(
      records, library: templates.load(), finished: workouts.load(),
      meals: await mealCaptures.logged(), at: Date())
    if let library = outcome.library { templates.save(library) }
    workouts.save(outcome.finished)
    for meal in outcome.meals { try await mealCaptures.log(meal) }
    if !outcome.corrections.isEmpty { await syncRecords(outcome.corrections) }
    let found = Restore.places(records)
    var added = Restore.Places()
    added.log = await places.restore(found.log)
    added.weighIns = await weighIns.restore(found.weighIns)
    added.mine = await myPlaces.restore(found.mine)
    return outcome.text + added.text
  }
}
