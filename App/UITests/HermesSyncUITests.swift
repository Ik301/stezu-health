import XCTest

/// S-028: Settings shows the Hermes sync row, "--" before the first sync; Sync now sends the
/// scenario's synthetic Health samples to the fake POST /sync and the row shows the time and the
/// fake GET /sync/status count. `-uitest` never syncs on its own, so the row starts empty.
final class HermesSyncUITests: XCTestCase {
  @MainActor
  func testSyncNowUpdatesStatusRow() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "sync")

    // Open Settings: the row is there with "--" and a Sync now button.
    let gear = app.element("home.settings")
    XCTAssertTrue(gear.waitForExistence(timeout: 30), "no gear on Home")
    gear.tap()
    XCTAssertTrue(app.element("screen.settings.title").waitForExistence(timeout: 10))
    let row = app.element("settings.sync.status")
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no Hermes sync row")
    XCTAssertEqual(row.label, "--", "the row shows a sync before the first one")
    let syncNow = app.element("settings.sync.now")
    XCTAssertTrue(syncNow.exists, "no Sync now button")

    // One tap: the row shows when it ran and the fake server's sample count.
    syncNow.tap()
    let updated = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label CONTAINS '3 samples'"), object: row)
    XCTAssertEqual(
      XCTWaiter().wait(for: [updated], timeout: 15), .completed, "row is \(row.label)")
    XCTAssertFalse(row.label.hasPrefix("--"), "no sync time: \(row.label)")
    XCTAssertFalse(row.label.contains("waiting"), "batches still wait: \(row.label)")
    saveScreenshot("s028-sync-row", of: app)
  }

  /// S-029: a logged meal joins the sync queue on its own (no tap) and reaches the fake POST /sync
  /// as one meal record; the Settings row's record count, from the fake GET /sync/status that
  /// counts the records it received, goes from 0 to 1.
  @MainActor
  func testLoggedMealIsSynced() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "sync-meals")

    // Before: the fake server holds no records.
    let gear = app.element("home.settings")
    XCTAssertTrue(gear.waitForExistence(timeout: 30), "no gear on Home")
    gear.tap()
    let row = app.element("settings.sync.status")
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no Hermes sync row")
    app.element("settings.sync.now").tap()
    wait(for: "label CONTAINS '0 records'", on: row)
    let settings = app.element("screen.settings.title")
    // A swipe on the title leaves the large sheet open, so drag it down from its grabber.
    for _ in 0..<3 where settings.exists {
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).press(
        forDuration: 0.1,
        thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
      sleep(2)
    }
    wait(for: "exists == false", on: settings)

    // Log the fixture match; nothing else is tapped for the sync.
    let card = app.element("home.card.food")
    XCTAssertTrue(card.waitForExistence(timeout: 10), "no food card on Home")
    card.tap()
    let shutter = app.element("food.shutter")
    XCTAssertTrue(shutter.waitForExistence(timeout: 10), "no shutter")
    wait(for: "isEnabled == true", on: shutter)
    shutter.tap()
    let match = app.element("food.match.title")
    XCTAssertTrue(match.waitForExistence(timeout: 15), "no match sheet")
    app.element("food.edit.log").tap()
    XCTAssertTrue(app.element("food.logged.toast").waitForExistence(timeout: 10), "no toast")

    // After: the fake server received the meal record, so the row counts one.
    app.element("nav.home").tap()
    XCTAssertTrue(gear.waitForExistence(timeout: 10), "not back on Home")
    gear.tap()
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no Hermes sync row")
    wait(for: "label CONTAINS ', 1 record'", on: row)
    XCTAssertFalse(row.label.contains("waiting"), "the meal still waits: \(row.label)")
    saveScreenshot("s029-meal-synced", of: app)
  }

  /// S-030: Day 1 with a set logged, undone and logged again, then Finish. With no sync tap the
  /// fake POST /sync gets the set records (the undone one as a tombstone) and one
  /// workout_session record, so the row's live records go from 0 to 2: the second set and the
  /// session. The undone set would make it 3 if its deletion had not arrived.
  @MainActor
  func testLoggedSetsAndFinishedWorkoutAreSynced() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "sync")

    // Before: the fake server holds no records.
    let gear = app.element("home.settings")
    XCTAssertTrue(gear.waitForExistence(timeout: 30), "no gear on Home")
    gear.tap()
    let row = app.element("settings.sync.status")
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no Hermes sync row")
    app.element("settings.sync.now").tap()
    wait(for: "label CONTAINS ', 0 records'", on: row)
    let settings = app.element("screen.settings.title")
    for _ in 0..<3 where settings.exists {  // drag the sheet down from its grabber
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).press(
        forDuration: 0.1,
        thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
      sleep(2)
    }
    wait(for: "exists == false", on: settings)

    // Start Day 1, log a set, undo it, log it again, Finish.
    let card = app.element("home.card.workout")
    XCTAssertTrue(card.waitForExistence(timeout: 10), "no Workout card on Home")
    card.tap()
    let start = app.element("workout.today.start")
    XCTAssertTrue(start.waitForExistence(timeout: 10), "no Start on the Workout screen")
    start.tap()
    let log = app.element("workout.logger.log")
    XCTAssertTrue(log.waitForExistence(timeout: 10), "the Log card did not open")
    let logged = app.element("workout.logger.logged.0")
    log.tap()
    XCTAssertTrue(logged.waitForExistence(timeout: 5), "the set was not logged")
    app.element("workout.logger.undo").tap()
    wait(for: "exists == false", on: logged)
    log.tap()
    XCTAssertTrue(logged.waitForExistence(timeout: 5), "the set was not logged again")
    app.element("workout.logger.finish").tap()
    XCTAssertTrue(app.element("workout.summary.done").waitForExistence(timeout: 10), "no summary")
    app.element("workout.summary.done").tap()  // S-044: Finish opens the summary; Done returns
    XCTAssertTrue(
      app.element("workout.session.0").waitForExistence(timeout: 10), "the session is not kept")

    // After: the fake server's live records are the second set and the session.
    app.element("nav.home").tap()
    XCTAssertTrue(gear.waitForExistence(timeout: 10), "not back on Home")
    gear.tap()
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no Hermes sync row")
    wait(for: "label CONTAINS ', 2 records'", on: row)
    XCTAssertFalse(row.label.contains("waiting"), "records still wait: \(row.label)")
    saveScreenshot("s030-workout-synced", of: app)
  }

  /// S-031: in the sync scenario one weigh-in (1 tap + Save) is saved on the phone, shows in the
  /// weight row and reaches the fake POST /sync as one weigh_in record, so the row's live
  /// records go from 0 to 1; deleting it in the Day view sends it with deleted: true, back to 0.
  @MainActor
  func testWeighInIsStoredLocallyAndSynced() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "sync")

    // Before: the fake server holds no records.
    let gear = app.element("home.settings")
    XCTAssertTrue(gear.waitForExistence(timeout: 30), "no gear on Home")
    gear.tap()
    let row = app.element("settings.sync.status")
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no Hermes sync row")
    app.element("settings.sync.now").tap()
    wait(for: "label CONTAINS ', 0 records'", on: row)
    closeSettings(app)

    // Weigh in once: the row shows it.
    let card = app.element("home.card.data")
    XCTAssertTrue(card.waitForExistence(timeout: 10), "no Data card on Home")
    card.tap()
    let connect = app.element("data.connect")
    XCTAssertTrue(connect.waitForExistence(timeout: 10), "no Connect on Data")
    connect.tap()
    let weighIn = app.element("data.weighIn")
    XCTAssertTrue(weighIn.waitForExistence(timeout: 10), "no Weigh in on the Weight row")
    weighIn.tap()
    let save = app.element("data.weighIn.save")
    XCTAssertTrue(save.waitForExistence(timeout: 10), "no weigh-in stepper")
    let value = app.element("data.weighIn.value").label
    save.tap()
    wait(for: "label == 'Weigh-ins: 1 of 7'", on: app.element("data.weight.coverage"))
    XCTAssertEqual(app.element("data.weight.trend").label, value, "the row is not the weigh-in")

    // The fake server received one weigh_in record.
    app.element("nav.home").tap()
    XCTAssertTrue(gear.waitForExistence(timeout: 10), "not back on Home")
    gear.tap()
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no Hermes sync row")
    wait(for: "label CONTAINS ', 1 record'", on: row)
    XCTAssertFalse(row.label.contains("waiting"), "the weigh-in still waits: \(row.label)")
    saveScreenshot("s031-weighin-synced", of: app)
    closeSettings(app)

    // Delete it in today's Day view (a second tap confirms).
    XCTAssertTrue(card.waitForExistence(timeout: 10), "no Data card on Home")
    card.tap()
    let open = app.element("data.weight.open")
    XCTAssertTrue(open.waitForExistence(timeout: 10), "no way into Weight")
    open.tap()
    let thisWeek = app.element("metric.week.0")
    XCTAssertTrue(thisWeek.waitForExistence(timeout: 10), "no weeks")
    thisWeek.tap()
    let today = (Calendar.current.component(.weekday, from: Date()) + 5) % 7  // Monday is 0
    let openToday = app.element("metric.day.\(today).open")
    XCTAssertTrue(openToday.waitForExistence(timeout: 10), "no way into today")
    openToday.tap()
    let first = app.element("day.record.0")
    wait(for: "label == 'Weigh-in'", on: first)
    XCTAssertEqual(app.element("day.record.0.detail").label, value)
    XCTAssertEqual(app.element("day.record.0.source").label, "From Stezu")
    let delete = app.element("day.record.0.delete")
    delete.tap()
    wait(for: "label == 'Confirm'", on: delete)
    delete.tap()
    XCTAssertTrue(app.element("day.empty").waitForExistence(timeout: 10), "not deleted")

    // The deletion reached the fake server: no live records again.
    app.element("metric.day.back").tap()
    app.element("metric.back").tap()
    app.element("metric.close").tap()
    let home = app.element("nav.home")
    XCTAssertTrue(home.waitForExistence(timeout: 10), "the Weight detail did not close")
    home.tap()
    XCTAssertTrue(gear.waitForExistence(timeout: 10), "not back on Home")
    gear.tap()
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no Hermes sync row")
    wait(for: "label CONTAINS ', 0 records'", on: row)
    XCTAssertFalse(row.label.contains("waiting"), "the deletion still waits: \(row.label)")
  }

  /// S-033: the background-sync scenario's launch is the debug hook: a visit is queued as if
  /// recorded while the app was closed, then the BGAppRefreshTask handler's pass runs once. With
  /// no tap, the fake POST /sync gets the scenario's three Health samples and the visit record,
  /// and Settings shows a background sync time while the foreground sync is still "--".
  @MainActor
  func testBackgroundSyncUpdatesStatus() {
    continueAfterFailure = false
    let app = UITestApp.launch(scenario: "background-sync")

    let gear = app.element("home.settings")
    XCTAssertTrue(gear.waitForExistence(timeout: 30), "no gear on Home")
    gear.tap()
    XCTAssertTrue(app.element("screen.settings.title").waitForExistence(timeout: 10))
    let background = app.element("settings.sync.background")
    XCTAssertTrue(background.waitForExistence(timeout: 10), "no Background sync row")
    wait(for: "label != '--'", on: background)

    // The fake server answered with the samples and counts the visit it received; nothing
    // waits, and the foreground row still shows no sync of its own.
    let row = app.element("settings.sync.status")
    wait(for: "label CONTAINS '3 samples'", on: row)
    wait(for: "label CONTAINS ', 1 record'", on: row)
    XCTAssertTrue(row.label.hasPrefix("--"), "a foreground sync ran: \(row.label)")
    XCTAssertFalse(row.label.contains("waiting"), "batches still wait: \(row.label)")
    saveScreenshot("s033-background-sync", of: app)
  }

  /// Drags the Settings sheet down from its grabber; a swipe on the title leaves it open.
  @MainActor
  private func closeSettings(_ app: XCUIApplication) {
    let settings = app.element("screen.settings.title")
    for _ in 0..<3 where settings.exists {
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).press(
        forDuration: 0.1,
        thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
      sleep(2)
    }
    wait(for: "exists == false", on: settings)
  }

  @MainActor
  private func wait(for format: String, on element: XCUIElement) {
    let met = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
    let result = XCTWaiter().wait(for: [met], timeout: 15)
    XCTAssertEqual(result, .completed, "\(format): \(element.exists ? element.label : "(gone)")")
  }
}
