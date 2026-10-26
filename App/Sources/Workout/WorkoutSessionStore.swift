import Foundation
import StezuCore

/// The workout in progress as one JSON file, written after every logged or undone set so a set
/// is stored the moment it is logged. Memory storage keeps nothing (each `-uitest` launch is new).
struct WorkoutSessionStore {
  let file: URL?

  init(storage: StorageMode) {
    switch storage {
    case .memory:
      file = nil
    case .disk:
      file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("active-workout.json")
    case .temporary(let folder):
      file = folder.appendingPathComponent("active-workout.json")
    }
  }

  /// The saved workout in progress, or nil when there is none or it cannot be read.
  func load() -> SetLogger? {
    let data = file.flatMap { try? Data(contentsOf: $0) }
    return data.flatMap { try? JSONDecoder().decode(SetLogger.self, from: $0) }
  }

  func save(_ logger: SetLogger) {
    guard let file, let data = try? JSONEncoder().encode(logger) else { return }
    try? FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: file, options: .atomic)
  }

  /// Forgets the workout in progress once it is finished or discarded.
  func clear() {
    guard let file else { return }
    try? FileManager.default.removeItem(at: file)
  }
}
