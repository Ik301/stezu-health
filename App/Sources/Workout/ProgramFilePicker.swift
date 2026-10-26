import Foundation
import StezuCore

/// Where Import program gets its file: the Files picker on the phone, or in `-uitest` a fixture
/// that hands back a synthetic program at once.
enum ProgramFilePicker: Sendable {
  case files
  case fixture(Data)
}

/// A picked file after its check (S-034): its templates, to confirm before they replace the
/// program, or the line the screen shows when it is refused.
enum ProgramPick: Equatable {
  case confirm([WorkoutTemplate])
  case refused(String)
}

extension WorkoutTemplateStore {
  /// Checks a picked file whole without changing anything.
  static func check(_ data: Data?) -> ProgramPick {
    guard let data else { return .refused("Import failed. The file could not be read.") }
    switch ProgramImport.parse(data) {
    case .success(let templates): return .confirm(templates)
    case .failure(let failure): return .refused("Import failed. \(failure.message)")
    }
  }

  /// The confirmation's question, naming the file's templates in order.
  static func question(_ templates: [WorkoutTemplate]) -> String {
    "Replace your program with \(templates.map(\.name).joined(separator: ", "))?"
  }

  /// Replaces the program with confirmed templates and saves the library. History is stored
  /// apart and nothing is queued for the server. Returns the line the screen shows.
  func replaceProgram(with templates: [WorkoutTemplate], in library: inout TemplateLibrary)
    -> String
  {
    library.replaceProgram(with: templates)
    save(library)
    return templates.count == 1 ? "Imported 1 template" : "Imported \(templates.count) templates"
  }

  /// Checks a file and, if it is valid, replaces the program with no confirmation; an
  /// unreadable or invalid file leaves the library as it was.
  func importProgram(_ data: Data?, into library: inout TemplateLibrary) -> String {
    switch Self.check(data) {
    case .confirm(let templates): return replaceProgram(with: templates, in: &library)
    case .refused(let line): return line
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
  /// The program the fixture picker returns: a generic two-template file, Push then Pull, with
  /// fewer templates than the seed (D-034). The "program-invalid" scenario returns one with a
  /// broken rep range instead.
  static func programFile(scenario: String?) -> Data {
    let repsHigh = scenario == "program-invalid" ? 6 : 12
    return Data(
      """
      {"seedVersion": 1, "templates": [
      {"key": "push", "name": "Push", "exercises": [
        {"key": "push-up", "name": "Push-up", "sets": 3, "repsLow": 8, "repsHigh": \(repsHigh), "restSeconds": 60},
        {"key": "bench-press", "name": "Bench press", "sets": 3, "repsLow": 6, "repsHigh": 10, "restSeconds": 150, "startPounds": 45}]},
      {"key": "pull", "name": "Pull", "exercises": [
        {"key": "barbell-row", "name": "Barbell row", "sets": 3, "repsLow": 6, "repsHigh": 10, "restSeconds": 150, "startPounds": 45},
        {"key": "biceps-curl", "name": "Biceps curl", "sets": 3, "repsLow": 10, "repsHigh": 15, "restSeconds": 60}]}]}
      """.utf8)
  }
}
