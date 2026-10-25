import XCTest

/// S-003: open Workout, see Day 1 as the black card with the other templates below, and Start.
final class WorkoutStartUITests: XCTestCase {
  @MainActor
  func testStartDayOneFromTemplates() {
    continueAfterFailure = false
    let app = UITestApp.launch()

    // Step 1: one tap to Workout. Day 1 is next on first launch, with its exercises.
    let card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card on Home")
    card.tap()
    XCTAssertTrue(app.element("screen.workout.title").waitForExistence(timeout: 10))
    let name = app.element("workout.today.name")
    XCTAssertTrue(name.waitForExistence(timeout: 10), "no next template card")
    XCTAssertTrue(name.label.hasPrefix("Day 1"), "next template is not Day 1: \(name.label)")
    let firstExercise = app.element("workout.today.exercise.0")
    XCTAssertTrue(firstExercise.exists, "the next template lists no exercises")
    XCTAssertTrue(firstExercise.label.contains("Bench press"), firstExercise.label)

    // Step 2: the generic seed's other four templates and Empty workout are rows below.
    for key in ["day-2", "day-3", "day-4", "day-5", "empty"] {
      XCTAssertTrue(app.element("workout.template.\(key)").exists, "no row for \(key)")
    }
    XCTAssertFalse(app.element("workout.template.day-1").exists, "Day 1 is also a row")
    for id in ["workout.week.sessions", "workout.week.sets"] {
      XCTAssertEqual(app.element(id).label, "--", "\(id) is not missing")
    }
    saveScreenshot("s003-workout-today", of: app)

    // Step 3: Start opens the logger on the first exercise, set 1 of 3, with its rep range.
    app.element("workout.today.start").tap()
    let exercise = app.element("workout.logger.exercise")
    XCTAssertTrue(exercise.waitForExistence(timeout: 10), "the logger did not open")
    XCTAssertEqual(exercise.label, "Bench press")
    XCTAssertEqual(app.element("workout.logger.set").label, "Set 1 of 3")
    XCTAssertEqual(app.element("workout.logger.reps").label, "6-10 reps")
    saveScreenshot("s003-logger-first-set", of: app)
  }
}
