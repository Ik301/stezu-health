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

    let message = store.importProgram(UITestFixtures.programFile(scenario: nil), into: &library)
    XCTAssertEqual(message, "Imported 2 templates")
    let reloaded = store.load(seed: seed)
    XCTAssertEqual(reloaded.templates.first?.name, "Day 1 Full body")
    XCTAssertEqual(reloaded.templates.last?.key, "day-6")
    XCTAssertEqual(
      store.importProgram(nil, into: &library), "Import failed. The file could not be read.")
  }
}
