import Foundation
import StezuCore

/// Where Import program gets its file: the Files picker on the phone, or in `-uitest` a fixture
/// that hands back a synthetic program at once.
enum ProgramFilePicker: Sendable {
  case files
  case fixture(Data)
}

extension WorkoutTemplateStore {
  /// Applies a picked program file and saves the library. Returns the line the screen shows; an
  /// unreadable or invalid file leaves the library as it was.
  func importProgram(_ data: Data?, into library: inout TemplateLibrary) -> String {
    guard let data else { return "Import failed. The file could not be read." }
    switch library.importProgram(data) {
    case .success(let count):
      save(library)
      return count == 1 ? "Imported 1 template" : "Imported \(count) templates"
    case .failure(let failure):
      return "Import failed. \(failure.message)"
    }
  }

  /// Reads a file the Files picker returned, which sits outside the app's sandbox.
  static func read(_ url: URL) -> Data? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    return try? Data(contentsOf: url)
  }
}

extension UITestFixtures {
  /// The program the fixture picker returns: a generic file that replaces Day 1 and adds Day 6
  /// (D-034). The "program-invalid" scenario returns one with a broken rep range instead.
  static func programFile(scenario: String?) -> Data {
    let repsHigh = scenario == "program-invalid" ? 6 : 12
    return Data(
      """
      {"seedVersion": 1, "templates": [
      {"key": "day-1", "name": "Day 1 Full body", "exercises": [
        {"key": "goblet-squat", "name": "Goblet squat", "sets": 3, "repsLow": 8, "repsHigh": \(repsHigh), "restSeconds": 90},
        {"key": "push-up", "name": "Push-up", "sets": 3, "repsLow": 8, "repsHigh": 15, "restSeconds": 60}]},
      {"key": "day-6", "name": "Day 6 Arms", "exercises": [
        {"key": "biceps-curl", "name": "Biceps curl", "sets": 3, "repsLow": 10, "repsHigh": 15, "restSeconds": 60}]}]}
      """.utf8)
  }
}
