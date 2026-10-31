import XCTest

/// S-035: a program file's add-on block (Abs) is not a day on Workout. While a workout runs, the
/// logger shows "+ Abs"; one tap appends its exercises after the day's own, and it stays one
/// session. The "program-addon" fixture is generic: Push and Pull with one exercise each, and
/// Abs with Cable crunch and Hanging leg raise (D-034).
final class WorkoutLoggerUITests: XCTestCase {
  /// Scrolls until the element can be tapped, then taps it.
  @MainActor
  private func tap(_ id: String, in app: XCUIApplication, up: Bool = true) {
    let element = app.element(id)
    XCTAssertTrue(element.waitForExistence(timeout: 10), "no \(id)")
    for _ in 0..<3 where !element.isHittable {
      if up { app.swipeUp() } else { app.swipeDown() }
    }
    element.tap()
  }

  @MainActor
  func testAddOnAppendsToCurrentWorkout() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "program-addon")
    let card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card on Home")
    card.tap()
    XCTAssertTrue(app.element("workout.today.name").waitForExistence(timeout: 10))

    // Step 1: after the import the Workout screen lists only the two days.
    tap("workout.import", in: app)
    let alert = app.alerts.firstMatch
    XCTAssertTrue(alert.waitForExistence(timeout: 10), "no Replace confirmation")
    alert.buttons["Replace"].firstMatch.tap()
    let message = app.element("workout.import.message")
    XCTAssertTrue(message.waitForExistence(timeout: 10), "the import showed no result")
    app.swipeDown()
    XCTAssertEqual(app.element("workout.today.name").label, "Push")
    XCTAssertTrue(app.element("workout.template.pull").exists, "Pull is not listed")
    XCTAssertFalse(app.element("workout.template.abs").exists, "the add-on is listed as a day")
    XCTAssertFalse(app.element("workout.template.push").exists, "Push is listed twice")

    // Step 2: the running workout offers "+ Abs" below the day's exercise.
    tap("workout.today.start", in: app, up: false)
    let exercise = app.element("workout.logger.exercise")
    XCTAssertTrue(exercise.waitForExistence(timeout: 10), "the logger did not open")
    XCTAssertEqual(exercise.label, "Bench press")
    let addOn = app.element("workout.logger.addon.abs")
    XCTAssertTrue(addOn.waitForExistence(timeout: 5), "no add-on button")
    XCTAssertEqual(addOn.label, "+ Abs")
    saveScreenshot("s035-addon-button", of: app)

    // One tap appends Abs and the button goes; the card finishes the day's exercise first.
    tap("workout.logger.addon.abs", in: app)
    let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: addOn)
    wait(for: [gone], timeout: 5)
    XCTAssertEqual(exercise.label, "Bench press", "the add-on jumped ahead of the day")
    tap("workout.logger.log", in: app, up: false)
    XCTAssertEqual(exercise.label, "Cable crunch", "the add-on does not follow the day")
    XCTAssertEqual(app.element("workout.logger.set").label, "Set 1 of 2")
    XCTAssertEqual(app.element("workout.logger.weight").label, "30 lb")
    tap("workout.logger.log", in: app, up: false)
    XCTAssertTrue(app.element("workout.logger.logged.0").waitForExistence(timeout: 5))
    XCTAssertEqual(app.element("workout.logger.set").label, "Set 2 of 2")
    XCTAssertTrue(app.element("workout.rest.countdown").exists, "no rest after the add-on set")
    saveScreenshot("s035-addon-appended", of: app)

    // Step 3: one Finish, one session under Push with the add-on exercise; the unlogged
    // Hanging leg raise is left out.
    tap("workout.logger.finish", in: app, up: false)
    tap("workout.summary.done", in: app, up: false)  // S-044: Finish opens the summary
    let row = app.element("workout.session.0")
    XCTAssertTrue(row.waitForExistence(timeout: 10), "the finished session is not shown")
    XCTAssertTrue(row.label.hasPrefix("Push"), row.label)
    XCTAssertTrue(row.label.hasSuffix("2 sets"), row.label)
    XCTAssertFalse(app.element("workout.session.1").exists, "the add-on made a second session")

    // Step 6: History shows one session containing the add-on exercise.
    tap("workout.history", in: app, up: false)
    let session = app.element("history.session.0.0")
    XCTAssertTrue(session.waitForExistence(timeout: 10), "no session in History")
    XCTAssertFalse(app.element("history.session.0.1").exists, "two sessions in History")
    session.tap()
    let first = app.element("history.exercise.0")
    XCTAssertTrue(first.waitForExistence(timeout: 10), "the session has no exercises")
    XCTAssertEqual(first.label, "Bench press")
    XCTAssertEqual(app.element("history.exercise.1").label, "Cable crunch")
    // S-055: a finished session's sets are chips, one per set.
    XCTAssertEqual(app.element("history.set.1.0").label, "30 x 10")
    XCTAssertFalse(app.element("history.set.1.1").exists, "a second Cable crunch set")
    XCTAssertFalse(app.element("history.exercise.2").exists, "an unlogged exercise was saved")
  }

  /// S-044: launch with the generic "workout-history" fixture (a Day 1 session 7 days ago with
  /// bench 60 x 8, 60 x 8, 60 x 7, and a newer Day 2 session with bench 65 x 5). Start the next
  /// template, log a set: the rest appears inside the card above the steppers and Log does not
  /// move. Skip it, log a heavier set, Finish: Undo reopens the session; Finish again shows the
  /// summary with the best set against the last Day 1, not the newer Day 2. Done returns.
  @MainActor
  func testInlineRestAndSummaryWithUndo() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "workout-history")
    let card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card on Home")
    card.tap()

    // Workout: the next template is the black card, listing its exercises.
    let name = app.element("workout.today.name")
    XCTAssertTrue(name.waitForExistence(timeout: 10), "no black card")
    XCTAssertEqual(name.label, "Day 1 Push")
    XCTAssertTrue(app.element("workout.today.exercise.0").label.hasPrefix("Bench press"))
    XCTAssertEqual(app.element("workout.week.sessions").label, "--")
    saveScreenshot("s044-workout", of: app)

    // Start (1 tap): the logger, with Finish at the top right.
    app.element("workout.today.start").tap()
    let log = app.element("workout.logger.log")
    let countdown = app.element("workout.rest.countdown")
    XCTAssertTrue(log.waitForExistence(timeout: 10), "the logger did not open")
    XCTAssertTrue(app.element("workout.logger.finish").exists, "no Finish")
    XCTAssertEqual(app.element("workout.logger.exercise").label, "Bench press")
    XCTAssertEqual(app.element("workout.logger.set").label, "Set 1 of 3")
    XCTAssertEqual(app.element("workout.logger.last").label, "Last 60 x 8, 7d ago")
    XCTAssertFalse(countdown.exists, "a rest runs before any set")
    let logFrame = log.frame

    // Log (1 tap): the rest runs inside the card, above the steppers; Log stays put.
    log.tap()
    XCTAssertTrue(countdown.waitForExistence(timeout: 5), "no rest after Log")
    XCTAssertEqual(log.frame.minY, logFrame.minY, accuracy: 1, "Log moved")
    XCTAssertGreaterThan(countdown.frame.minY, app.element("workout.logger.last").frame.maxY)
    XCTAssertLessThan(countdown.frame.maxY, app.element("workout.logger.weight").frame.minY)
    XCTAssertTrue(app.element("workout.logger.logged.0").exists, "the set is not listed")
    XCTAssertEqual(app.element("workout.logger.set").label, "Set 2 of 3")
    let next = app.element("workout.logger.next")
    XCTAssertTrue(next.exists, "no dashed next-set row")
    XCTAssertTrue(next.label.contains("Last 60 x 8"), next.label)
    saveScreenshot("s044-logger-rest", of: app)

    // Skip ends the rest; a heavier second set.
    app.element("workout.rest.skip").tap()
    XCTAssertTrue(countdown.waitForNonExistence(timeout: 5), "Skip left the rest")
    XCTAssertEqual(log.frame.minY, logFrame.minY, accuracy: 1, "Log moved after Skip")
    app.element("workout.logger.weight.plus").tap()
    XCTAssertEqual(app.element("workout.logger.weight").label, "65 lb")
    log.tap()
    XCTAssertTrue(app.element("workout.logger.logged.1").waitForExistence(timeout: 5))

    // Finish (1 tap), then Undo within 8 s: the same session is back on the logger.
    app.element("workout.logger.finish").tap()
    let undo = app.element("workout.summary.undo")
    XCTAssertTrue(undo.waitForExistence(timeout: 5), "no Undo on the summary")
    undo.tap()
    XCTAssertTrue(log.waitForExistence(timeout: 10), "Undo did not reopen the logger")
    XCTAssertTrue(app.element("workout.logger.logged.1").exists, "the sets were lost")
    XCTAssertEqual(app.element("workout.logger.set").label, "Set 3 of 3")

    // Finish again: the summary, compared with the last Day 1 (60 x 8), not Day 2 (65 x 5).
    app.element("workout.logger.finish").tap()
    let change = app.element("workout.summary.change.0")
    XCTAssertTrue(change.waitForExistence(timeout: 10), "no summary after Finish")
    XCTAssertEqual(change.label, "+5 lb")
    XCTAssertTrue(app.element("workout.summary.exercise.0").label.contains("60 x 8, 65 x 8"))
    XCTAssertEqual(
      app.element("workout.summary.versus").label, "Exercises vs last Day 1 Push, 7d ago")
    XCTAssertEqual(app.element("workout.summary.sets").label, "2")
    XCTAssertEqual(app.element("workout.summary.volume").label, "1,000 lb", "60x8 + 65x8")
    let duration = app.element("workout.summary.duration").label
    XCTAssertTrue(duration.hasSuffix(" s") || duration.hasSuffix(" min"), duration)
    let health = app.element("workout.summary.health")
    let inHealth = expectation(
      for: NSPredicate(format: "label == %@", "In Health"), evaluatedWith: health)
    wait(for: [inHealth], timeout: 10)
    saveScreenshot("s044-summary", of: app)

    // Done returns to Workout: one Day 1 session with both sets, not two.
    app.element("workout.summary.done").tap()
    let row = app.element("workout.session.0")
    XCTAssertTrue(row.waitForExistence(timeout: 10), "Done did not return to Workout")
    XCTAssertTrue(row.label.hasPrefix("Day 1 Push"), row.label)
    XCTAssertTrue(row.label.contains("2 sets"), row.label)
    XCTAssertFalse(app.element("workout.session.1").exists, "Undo made a second session")
  }

  /// S-046: start the next template ("workout-history": Day 1 Push, five exercises, Bench press
  /// first). The nav circles are gone and the TopBar reads Day 1 Push with Finish. Skip
  /// exercise moves the card to Overhead press and the progress to exercise 2; Finish from the
  /// TopBar leaves the skipped Bench press out of the session.
  @MainActor
  func testTopBarFinishSkipAndHiddenNav() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "workout-history")
    let card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 30), "no Workout card on Home")
    card.tap()
    let start = app.element("workout.today.start")
    XCTAssertTrue(start.waitForExistence(timeout: 10), "no Start")
    XCTAssertTrue(app.element("nav.circle.workout").exists, "no area nav on Workout")

    // Start: no area nav, Home stays, the TopBar holds the template name and Finish.
    start.tap()
    let exercise = app.element("workout.logger.exercise")
    XCTAssertTrue(exercise.waitForExistence(timeout: 10), "the logger did not open")
    XCTAssertEqual(exercise.label, "Bench press")
    for area in ["data", "food", "workout"] {
      XCTAssertFalse(app.element("nav.circle.\(area)").exists, "\(area) circle while logging")
    }
    XCTAssertTrue(app.element("nav.home").exists, "Home left the TopBar")
    let title = app.element("screen.workout.title")
    XCTAssertEqual(title.label, "Day 1 Push")
    let finish = app.element("workout.logger.finish")
    XCTAssertTrue(finish.exists, "no Finish")
    XCTAssertLessThanOrEqual(finish.frame.maxY, title.frame.minY + 1, "Finish is not in the bar")
    let progress = app.element("workout.logger.progress")
    XCTAssertEqual(progress.label, "Exercise 1 of 5")
    XCTAssertTrue(
      app.element("workout.logger.upNext").label.hasPrefix("Up next: Overhead press"),
      app.element("workout.logger.upNext").label)
    saveScreenshot("s046-logger-topbar", of: app)

    // Skip exercise (ellipsis menu): the card moves on without logging, the progress advances.
    tap("workout.logger.menu", in: app, up: false)
    let skip = app.element("workout.logger.skipExercise")
    if skip.waitForExistence(timeout: 3) { skip.tap() } else { app.buttons["Skip exercise"].tap() }
    XCTAssertEqual(exercise.label, "Overhead press", "Skip exercise did not move on")
    XCTAssertEqual(app.element("workout.logger.set").label, "Set 1 of 3")
    XCTAssertFalse(app.element("workout.logger.logged.0").exists, "the skip logged a set")
    XCTAssertEqual(progress.label, "Exercise 2 of 5")
    XCTAssertTrue(app.element("workout.logger.upNext").label.hasPrefix("Up next: Incline"))

    // One set of Overhead press, then the progress row under the logged set.
    tap("workout.logger.log", in: app, up: false)
    XCTAssertTrue(app.element("workout.logger.logged.0").waitForExistence(timeout: 5))
    for _ in 0..<3 where !progress.isHittable { app.swipeUp() }
    XCTAssertGreaterThan(progress.frame.minY, app.element("workout.logger.logged.0").frame.maxY)
    XCTAssertEqual(progress.label, "Exercise 2 of 5")
    saveScreenshot("s046-progress", of: app)

    // Finish from the TopBar (1 tap): the summary has Overhead press only.
    finish.tap()
    let first = app.element("workout.summary.exercise.0")
    XCTAssertTrue(first.waitForExistence(timeout: 10), "Finish opened no summary")
    XCTAssertTrue(first.label.hasPrefix("Overhead press"), first.label)
    XCTAssertFalse(app.element("workout.summary.exercise.1").exists, "the skip was saved")
    app.element("workout.summary.done").tap()
    XCTAssertTrue(
      app.element("nav.circle.workout").waitForExistence(timeout: 10), "the nav did not return")
  }
}
