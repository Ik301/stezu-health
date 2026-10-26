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

  // D-083 changed this test: an import now replaces the whole program instead of upserting, so
  // "A" is gone after the first import and "B mine" after the second.
  func testImportUpsertsTemplatesByKey() throws {
    var library = seededLibrary()

    let first = library.importProgram(try file([template("b", "B mine"), template("c", "C")]))
    XCTAssertEqual(first, .success(2))
    XCTAssertEqual(library.templates.map(\.name), ["B mine", "C"])

    // A second import with the same key replaces the earlier import rather than adding a copy.
    let second = library.importProgram(try file([template("c", "C v2")]))
    XCTAssertEqual(second, .success(1))
    XCTAssertEqual(library.templates.map(\.name), ["C v2"])
    XCTAssertEqual(library.seedVersion, 1, "an import is not a seed")

    // Imported templates survive a newer bundled seed, like edits do.
    library.upsert(WorkoutSeed(seedVersion: 2, templates: [template("b", "B seed 2")]))
    XCTAssertEqual(library.templates.map(\.name), ["C v2"])
  }

  func testImportReplacesWholeProgramInFileOrder() throws {
    var library = seededLibrary()
    library.upsert(WorkoutSeed(seedVersion: 2, templates: [template("c", "C")]))
    XCTAssertEqual(library.templates.map(\.key), ["a", "b", "c"])
    // A workout started from "b" before the import keeps its own copy of the exercises (D-046).
    var bExercise = TemplateExercise(
      key: "x", name: "X", sets: 3, repsLow: 8, repsHigh: 12, restSeconds: 60)
    bExercise.startPounds = 45
    let started = WorkoutTemplate(key: "b", name: "B", exercises: [bExercise])
    var logger = SetLogger(template: started, startedAt: Date(timeIntervalSince1970: 0))

    let result = library.importProgram(try file([template("pull", "Pull"), template("a", "A2")]))
    XCTAssertEqual(result, .success(2))
    XCTAssertEqual(library.templates.map(\.key), ["pull", "a"], "exactly the file, in its order")
    XCTAssertEqual(library.templates.map(\.name), ["Pull", "A2"])
    XCTAssertTrue(library.programImported)
    XCTAssertEqual(library.next(after: nil)?.key, "pull")
    // Removed templates keep their names, so their past sessions show under them in History.
    XCTAssertEqual(library.names, ["pull": "Pull", "a": "A2", "b": "B", "c": "C"])

    XCTAssertNotNil(logger.log(at: Date(timeIntervalSince1970: 60)), "the open workout logs")
    XCTAssertEqual(logger.template.exercises.map(\.name), ["X"])
    XCTAssertEqual(logger.session.templateKey, "b")
    XCTAssertEqual(logger.session.sets(for: "X")?.count, 1)
  }

  func testSeedNeverRestoresRemovedTemplates() throws {
    var library = seededLibrary()
    XCTAssertEqual(library.importProgram(try file([template("push", "Push")])), .success(1))

    let newer = WorkoutSeed(
      seedVersion: 5, templates: [template("a", "A v5"), template("b", "B v5"), template("d", "D")])
    XCTAssertFalse(library.upsert(newer), "a seed applied after an import")
    XCTAssertEqual(library.templates.map(\.key), ["push"])

    // The flag is saved with the library, so a relaunch skips the seed too.
    let saved = try JSONEncoder().encode(library)
    var reloaded = try JSONDecoder().decode(TemplateLibrary.self, from: saved)
    XCTAssertEqual(reloaded, library)
    XCTAssertTrue(reloaded.programImported)
    XCTAssertFalse(reloaded.upsert(newer))
    XCTAssertEqual(reloaded.templates.map(\.key), ["push"])
    XCTAssertEqual(reloaded.names["a"], "A", "a removed name survives the save")
  }

  func testOldLibraryFileDecodesWithoutFlag() throws {
    // A library file saved before S-034: no programImported, no removedNames.
    let old = Data(
      #"""
      {"seedVersion": 1, "editedKeys": ["a"], "templates": [
        {"key": "a", "name": "A", "exercises": []},
        {"key": "b", "name": "B", "exercises": []}]}
      """#.utf8)
    var library = try JSONDecoder().decode(TemplateLibrary.self, from: old)
    XCTAssertFalse(library.programImported)
    XCTAssertEqual(library.templates.map(\.key), ["a", "b"])
    XCTAssertEqual(library.editedKeys, ["a"])
    XCTAssertEqual(library.names, ["a": "A", "b": "B"])

    // Without the flag a newer seed still upserts, skipping the edited key, as before.
    XCTAssertTrue(
      library.upsert(
        WorkoutSeed(seedVersion: 2, templates: [template("a", "A v2"), template("b", "B v2")])))
    XCTAssertEqual(library.templates.map(\.name), ["A", "B v2"])
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
