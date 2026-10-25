import Foundation
import StezuCore
import XCTest

// Templates here are generic examples, not anyone's program (D-034).
final class WorkoutTemplateTests: XCTestCase {
  /// The seed the app bundles, read from the repo so core and app test the same file.
  private var bundledSeedURL: URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { url.deleteLastPathComponent() }
    return url.appendingPathComponent("App/Sources/Workout/PrebuiltWorkouts.json")
  }

  private func template(_ key: String, _ name: String, sets: Int = 3) -> WorkoutTemplate {
    WorkoutTemplate(
      key: key, name: name,
      exercises: [
        TemplateExercise(
          key: "\(key)-a", name: "\(name) A", sets: sets, repsLow: 8, repsHigh: 12,
          restSeconds: 90)
      ])
  }

  func testSeedDecodesFiveTemplates() throws {
    let seed = try WorkoutSeed.decode(Data(contentsOf: bundledSeedURL))

    XCTAssertGreaterThanOrEqual(seed.seedVersion, 1)
    XCTAssertEqual(seed.templates.count, 5)
    XCTAssertEqual(Set(seed.templates.map(\.key)).count, 5, "template keys must be unique")
    XCTAssertTrue(seed.templates[0].name.hasPrefix("Day 1"))
    for template in seed.templates {
      XCTAssertFalse(template.exercises.isEmpty, "\(template.key) has no exercises")
      for exercise in template.exercises {
        XCTAssertGreaterThanOrEqual(exercise.sets, 1)
        XCTAssertGreaterThanOrEqual(exercise.repsLow, 1)
        XCTAssertLessThanOrEqual(exercise.repsLow, exercise.repsHigh)
        XCTAssertGreaterThan(exercise.restSeconds, 0)
      }
    }
    XCTAssertEqual(
      TemplateExercise(
        key: "x", name: "X", sets: 1, repsLow: 8, repsHigh: 12, restSeconds: 60
      ).repRange, "8-12")
  }

  func testSeedUpsertKeepsEditedTemplates() {
    var library = TemplateLibrary()
    XCTAssertTrue(
      library.upsert(
        WorkoutSeed(seedVersion: 1, templates: [template("a", "A"), template("b", "B")])))

    var editedA = template("a", "A")
    editedA.name = "A (mine)"
    library.edit(editedA)
    library.edit(template("custom", "Custom"))

    let v2 = WorkoutSeed(
      seedVersion: 2,
      templates: [template("a", "A2"), template("b", "B2", sets: 4), template("c", "C")])
    XCTAssertTrue(library.upsert(v2))
    XCTAssertEqual(library.seedVersion, 2)
    XCTAssertEqual(library.templates.map(\.key), ["a", "b", "custom", "c"])
    XCTAssertEqual(library.templates.map(\.name), ["A (mine)", "B2", "Custom", "C"])
    XCTAssertEqual(library.templates[1].exercises.first?.sets, 4)

    // An equal or older seed changes nothing.
    let before = library
    XCTAssertFalse(library.upsert(WorkoutSeed(seedVersion: 2, templates: [template("b", "Old")])))
    XCTAssertFalse(library.upsert(WorkoutSeed(seedVersion: 1, templates: [template("b", "Old")])))
    XCTAssertEqual(library, before)
  }

  func testRotationPicksNextTemplate() {
    var library = TemplateLibrary()
    XCTAssertNil(library.next(after: nil), "no templates means no next template")
    library.upsert(
      WorkoutSeed(
        seedVersion: 1,
        templates: [
          template("day-1", "Day 1"), template("day-2", "Day 2"), template("day-3", "Day 3"),
        ]
      ))

    XCTAssertEqual(library.next(after: nil)?.key, "day-1", "first launch starts at Day 1")
    XCTAssertEqual(library.next(after: "day-1")?.key, "day-2")
    XCTAssertEqual(library.next(after: "day-3")?.key, "day-1", "the rotation wraps")
    XCTAssertEqual(library.next(after: "deleted")?.key, "day-1")
  }
}
