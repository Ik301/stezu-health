import Foundation
import StezuCore

/// A meal photo saved on the phone at the shutter, before anything is sent to the server.
struct CapturedMeal: Sendable, Equatable, Identifiable, Codable {
  let id: UUID
  let capturedAt: Date
}

/// Captured meals as two files each in one folder, `<id>.jpg` and `<id>.json`, so a relaunch
/// finds them. Memory mode (`-uitest`) uses a fresh temporary folder, so each launch starts empty.
actor MealCaptureStore {
  private let folder: URL

  init(storage: StorageMode) {
    switch storage {
    case .memory: folder = FileManager.default.temporaryDirectory.appending(path: "\(UUID())")
    case .temporary(let root): folder = root.appending(path: "meals")
    case .disk: folder = URL.applicationSupportDirectory.appending(path: "meals")
    }
  }

  func save(photo: Data, at date: Date) throws -> CapturedMeal {
    let meal = CapturedMeal(id: UUID(), capturedAt: date)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try photo.write(to: folder.appending(path: "\(meal.id).jpg"), options: .atomic)
    try JSONEncoder().encode(meal).write(to: folder.appending(path: "\(meal.id).json"))
    return meal
  }

  /// Every captured meal, oldest first.
  func all() -> [CapturedMeal] {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path())) ?? []
    return files.filter { $0.hasSuffix(".json") }
      .compactMap { try? JSONDecoder().decode(CapturedMeal.self, from: file(named: $0) ?? Data()) }
      .sorted { $0.capturedAt < $1.capturedAt }
  }

  func photo(for id: UUID) -> Data? { file(named: "\(id).jpg") }

  /// Keeps the server's reply for a meal as `<id>.scan`; a meal without one is still pending.
  func saveReply(_ reply: Data, for id: UUID) throws {
    try reply.write(to: folder.appending(path: "\(id).scan"), options: .atomic)
  }

  /// Every captured meal with its saved match, oldest first. Nothing here deletes a meal.
  func queue() -> MealQueue {
    MealQueue(
      all().map { meal in
        let match = file(named: "\(meal.id).scan").flatMap { try? PhotoMatchClient.decode($0) }
        return QueuedMeal(id: meal.id, capturedAt: meal.capturedAt, match: match)
      })
  }

  private func file(named name: String) -> Data? {
    try? Data(contentsOf: folder.appending(path: name))
  }
}

/// The shutter: take one photo and save it locally. It makes no network call, so matching (which
/// starts from the saved meal) can fail or wait for a connection without losing the photo.
struct MealCapture: Sendable {
  let photoSource: any PhotoSource
  let store: MealCaptureStore
  var now: @Sendable () -> Date = { Date() }

  init(environment: AppEnvironment) {
    photoSource = environment.photoSource
    store = environment.mealCaptures
  }

  func shutter() async throws -> CapturedMeal {
    let photo = try await photoSource.capturePhoto()
    return try await store.save(photo: photo, at: now())
  }
}
