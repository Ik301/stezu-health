import Foundation
import StezuCore

/// Finished workouts as one JSON file, oldest first, rewritten after each Finish. Memory storage
/// keeps nothing, so a `-uitest` launch starts with none.
struct FinishedWorkoutStore {
  let file: URL?

  init(storage: StorageMode) {
    switch storage {
    case .memory:
      file = nil
    case .disk:
      file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("finished-workouts.json")
    case .temporary(let folder):
      file = folder.appendingPathComponent("finished-workouts.json")
    }
  }

  /// The saved workouts; none when there is no file or it cannot be read.
  func load() -> [FinishedWorkout] {
    let data = file.flatMap { try? Data(contentsOf: $0) }
    return data.flatMap { try? JSONDecoder().decode([FinishedWorkout].self, from: $0) } ?? []
  }

  func save(_ workouts: [FinishedWorkout]) {
    guard let file, let data = try? JSONEncoder().encode(workouts) else { return }
    try? FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: file, options: .atomic)
  }
}
