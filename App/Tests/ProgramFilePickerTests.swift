import StezuCore
import XCTest

@testable import StezuHealth

final class ProgramFilePickerTests: XCTestCase {
  func testImportedProgramIsSavedAndInvalidFixtureIsRefused() throws {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WorkoutTemplateStore(storage: .temporary(folder))
    let seed = try XCTUnwrap(WorkoutTemplateStore.bundledSeed())

    var library = store.load(seed: seed)
    let refused = store.importProgram(
      UITestFixtures.programFile(scenario: "program-invalid"), into: &library)
    XCTAssertTrue(refused.hasPrefix("Import failed."), refused)
    XCTAssertEqual(library, store.load(seed: seed))

    // S-034: a valid file is checked first and named in the confirmation; nothing changes yet.
    guard
      case .confirm(let templates) = WorkoutTemplateStore.check(
        UITestFixtures.programFile(scenario: nil))
    else { return XCTFail("the fixture was refused") }
    XCTAssertEqual(
      WorkoutTemplateStore.question(templates), "Replace your program with Push, Pull?")
    XCTAssertEqual(library, store.load(seed: seed))

    // D-083 changed these expectations: the fixture is now Push and Pull, and it replaces the
    // whole program, so the reload has exactly those two and the seed does not come back.
    let message = store.importProgram(UITestFixtures.programFile(scenario: nil), into: &library)
    XCTAssertEqual(message, "Imported 2 templates")
    let reloaded = store.load(seed: seed)
    XCTAssertEqual(reloaded.templates.map(\.name), ["Push", "Pull"])
    XCTAssertEqual(reloaded.templates.last?.key, "pull")
    XCTAssertEqual(reloaded.names["day-2"], "Day 2 Pull")
    XCTAssertEqual(
      store.importProgram(nil, into: &library), "Import failed. The file could not be read.")
  }
}
