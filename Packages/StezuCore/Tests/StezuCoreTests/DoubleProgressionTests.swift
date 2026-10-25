import Foundation
import StezuCore
import XCTest

// All weights, reps and ranges are made-up example numbers, not anyone's data.
final class DoubleProgressionTests: XCTestCase {
  private var historyConfig: WorkoutHistoryConfig {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return WorkoutHistoryConfig(calendar: calendar)
  }

  private let start = Date(timeIntervalSince1970: 1_700_000_000)

  private func day(_ offset: Int, minute: Int = 0) -> Date {
    start.addingTimeInterval(Double(offset) * 86_400 + Double(minute) * 60)
  }

  /// One earlier session of "Row" with the given (pounds, reps) sets, read three days later.
  private func last(_ sets: [(Double?, Int)]) -> LastSessionNumbers? {
    var session = WorkoutSession(startedAt: day(0))
    for (index, set) in sets.enumerated() {
      session.logSet("Row", pounds: set.0, reps: set.1, at: day(0, minute: index * 3 + 1))
    }
    return WorkoutHistory.lastSession(
      of: "Row", before: day(3), in: [session], config: historyConfig)
  }

  func testAddRepsBelowTopOfRange() throws {
    let config = try XCTUnwrap(DoubleProgression.Config(repRange: 6...10, weightStepPounds: 2.5))
    // A lighter warm-up set, then three working sets; one is already at the top.
    let lastSession = last([(40, 10), (80, 10), (80, 8), (80, 7)])

    let suggestion = try XCTUnwrap(DoubleProgression.suggest(after: lastSession, config: config))

    XCTAssertEqual(suggestion.exercise, "Row")
    XCTAssertEqual(suggestion.action, .addReps)
    XCTAssertEqual(suggestion.pounds, 80)
    XCTAssertEqual(suggestion.reps, [10, 9, 8])
    XCTAssertEqual(suggestion.confidence.level, .high)
    XCTAssertTrue(suggestion.confidence.reason.contains("2 of 3"))

    // Bodyweight below the top stays bodyweight: nil pounds, never 0.
    let bodyweight = try XCTUnwrap(
      DoubleProgression.suggest(after: last([(nil, 6), (nil, 5)]), config: config))
    XCTAssertEqual(bodyweight.action, .addReps)
    XCTAssertNil(bodyweight.pounds)
    XCTAssertEqual(bodyweight.reps, [7, 6])
  }

  func testAddWeightWhenAllSetsHitTop() throws {
    let config = try XCTUnwrap(DoubleProgression.Config(repRange: 6...10, weightStepPounds: 2.5))
    let lastSession = last([(80, 10), (80, 11), (80, 10)])

    let suggestion = try XCTUnwrap(DoubleProgression.suggest(after: lastSession, config: config))

    XCTAssertEqual(suggestion.action, .addWeight)
    XCTAssertEqual(suggestion.pounds, 82.5)
    XCTAssertEqual(suggestion.reps, [6, 6, 6])

    // Default config and a different range and step are both honoured.
    let defaults = try XCTUnwrap(DoubleProgression.Config())
    XCTAssertEqual(defaults.repRange, 8...12)
    XCTAssertEqual(
      DoubleProgression.suggest(after: lastSession, config: defaults)?.action, .addReps)
    let wide = try XCTUnwrap(DoubleProgression.Config(repRange: 3...5, weightStepPounds: 10))
    XCTAssertEqual(DoubleProgression.suggest(after: lastSession, config: wide)?.pounds, 90)
    XCTAssertEqual(DoubleProgression.suggest(after: lastSession, config: wide)?.reps, [3, 3, 3])

    // Invalid settings are rejected rather than producing a suggestion.
    XCTAssertNil(DoubleProgression.Config(repRange: 0...5, weightStepPounds: 5))
    XCTAssertNil(DoubleProgression.Config(repRange: 8...12, weightStepPounds: 0))
    XCTAssertNil(DoubleProgression.Config(repRange: 8...12, weightStepPounds: .nan))
  }

  func testNoSuggestionWithoutLastSession() throws {
    let config = try XCTUnwrap(DoubleProgression.Config())
    XCTAssertNil(DoubleProgression.suggest(after: nil, config: config))

    // An exercise never done before has no last session, so no suggestion (not 0 reps or 0 lb).
    let other = WorkoutSession(startedAt: day(0))
    let lastSession = WorkoutHistory.lastSession(
      of: "Row", before: day(3), in: [other], config: historyConfig)
    XCTAssertNil(DoubleProgression.suggest(after: lastSession, config: config))
  }
}
