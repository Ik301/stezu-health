import Foundation
import XCTest

@testable import StezuCore

final class ProgramImportTests: XCTestCase {
  private func template(_ key: String, _ name: String, sets: Int = 3) -> WorkoutTemplate {
    WorkoutTemplate(
      key: key, name: name,
      exercises: [
        TemplateExercise(key: "x", name: "X", sets: sets, repsLow: 8, repsHigh: 12, restSeconds: 60)
      ])
  }

  private func file(_ templates: [WorkoutTemplate]) throws -> Data {
    try JSONEncoder().encode(WorkoutSeed(seedVersion: 1, templates: templates))
  }

  private func seededLibrary() -> TemplateLibrary {
    var library = TemplateLibrary()
    library.upsert(
      WorkoutSeed(seedVersion: 1, templates: [template("a", "A"), template("b", "B")]))
    return library
  }

  func testImportUpsertsTemplatesByKey() throws {
    var library = seededLibrary()

    let first = library.importProgram(try file([template("b", "B mine"), template("c", "C")]))
    XCTAssertEqual(first, .success(2))
    XCTAssertEqual(library.templates.map(\.name), ["A", "B mine", "C"])

    // A second import with the same key replaces the earlier import rather than adding a copy.
    let second = library.importProgram(try file([template("c", "C v2")]))
    XCTAssertEqual(second, .success(1))
    XCTAssertEqual(library.templates.map(\.name), ["A", "B mine", "C v2"])
    XCTAssertEqual(library.seedVersion, 1, "an import is not a seed")

    // Imported templates survive a newer bundled seed, like edits do.
    library.upsert(WorkoutSeed(seedVersion: 2, templates: [template("b", "B seed 2")]))
    XCTAssertEqual(library.templates.map(\.name), ["A", "B mine", "C v2"])
  }

  func testInvalidFileChangesNothing() throws {
    let original = seededLibrary()
    let cases: [(Data, ProgramImport.Failure)] = [
      (Data("not json".utf8), .unreadable("invalid JSON")),
      (Data(#"{"seedVersion": 1}"#.utf8), .unreadable("missing \"templates\"")),
      (try file([]), .noTemplates),
      (
        try file([template("a", "New A"), template("a", "Again")]),
        .invalid("Template key \"a\" appears twice.")
      ),
      (
        try file([template("b", "New B"), template("d", "D", sets: 0)]),
        .invalid("X in D needs at least 1 set.")
      ),
    ]
    for (data, failure) in cases {
      var library = original
      XCTAssertEqual(library.importProgram(data), .failure(failure))
      XCTAssertEqual(library, original, "a refused file changed the library")
      XCTAssertFalse(failure.message.isEmpty)
    }
  }
}
