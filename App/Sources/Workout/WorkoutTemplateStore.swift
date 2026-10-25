import Foundation
import StezuCore

/// The template library as one JSON file, with the bundled PrebuiltWorkouts.json applied at
/// launch. Memory storage keeps nothing, so every `-uitest` launch starts from the seed.
struct WorkoutTemplateStore {
  let file: URL?

  init(storage: StorageMode) {
    switch storage {
    case .memory:
      file = nil
    case .disk:
      file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("workout-templates.json")
    case .temporary(let folder):
      file = folder.appendingPathComponent("workout-templates.json")
    }
  }

  static func bundledSeed(in bundle: Bundle = .main) -> WorkoutSeed? {
    let url = bundle.url(forResource: "PrebuiltWorkouts", withExtension: "json")
    return url.flatMap { try? WorkoutSeed.decode(Data(contentsOf: $0)) }
  }

  /// The stored library with a newer bundled seed upserted by key; saved when the seed changed it.
  func load(seed: WorkoutSeed? = bundledSeed()) -> TemplateLibrary {
    let data = file.flatMap { try? Data(contentsOf: $0) }
    var library =
      data.flatMap { try? JSONDecoder().decode(TemplateLibrary.self, from: $0) }
      ?? TemplateLibrary()
    if let seed, library.upsert(seed) { save(library) }
    return library
  }

  func save(_ library: TemplateLibrary) {
    guard let file, let data = try? JSONEncoder().encode(library) else { return }
    try? FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: file, options: .atomic)
  }
}
