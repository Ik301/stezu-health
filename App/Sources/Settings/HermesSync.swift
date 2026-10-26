import Foundation
import StezuCore

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
    var parts = [state.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "--"]
    if let samples = state.samplesTotal { parts.append("\(samples) samples") }
    if let records = state.recordsTotal {
      parts.append("\(records) record\(records == 1 ? "" : "s")")
    }
    if !state.pending.isEmpty { parts.append("\(state.pending.count) waiting") }
    return parts.joined(separator: ", ")
  }
}

extension AppEnvironment {
  /// One pass; Health once connected (S-020) or faked. Unconfigured or offline: the queue waits.
  @discardableResult
  func syncHermes() async -> SyncState {
    let connected = isUITest || healthConnection.isConnected
    return await healthSync.run(health: connected ? healthStore : nil, transport: vmTransport)
  }

  /// Open, foreground and Finish, off the main actor. `-uitest` syncs only on Sync now.
  func syncHermesInBackground() {
    guard !isUITest else { return }
    Task.detached(priority: .utility) { await self.syncHermes() }
  }

  /// S-029: a logged or edited meal, or a tombstone when `meal` is nil, joins the sync queue
  /// (saved before this returns), then a pass runs off the main actor, under `-uitest` too.
  func syncMeal(_ meal: LoggedMeal?, id: UUID, edited: Bool = false) async {
    let record = meal.map { SyncRecord.meal($0, edited: edited, at: Date()) }
    await healthSync.enqueue([record ?? .deletedMeal(id, at: Date())])
    Task.detached(priority: .utility) { await self.syncHermes() }
  }
}
