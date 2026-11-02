import Foundation
import XCTest

@testable import StezuCore

/// S-057 (D-143): records read back from GET /records rebuild the program, the finished
/// sessions (from their set records) and the meals, merged by id. Every value is made up (D-034).
final class RestoreTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)
  private var push: String { WorkoutFinish.externalID(for: WorkoutSession(startedAt: start)) }
  private var pull: String {
    WorkoutFinish.externalID(for: WorkoutSession(startedAt: start + 86_400))
  }
  private let mealID = UUID(uuidString: "8E2D4C6A-0000-4000-8000-000000000008")!

  private func stamp(_ offset: TimeInterval) -> String {
    SyncRecord.stamp(start + offset, Calendar(identifier: .gregorian))
  }

  private func set(
    _ session: String, _ name: String, _ key: String, _ pounds: Double?, at offset: TimeInterval,
    template: String
  ) -> [String: Any] {
    [
      "id": "\(session).set.\(Int64((start + offset).timeIntervalSince1970 * 1000))",
      "session_id": session, "exercise_name": name, "exercise_key": key,
      "template_key": template, "pounds": pounds.map { $0 as Any } ?? NSNull(), "reps": 8,
      "logged_at": stamp(offset),
      "kind": "working",
    ]
  }

  private func record(_ kind: String, _ payload: [String: Any]) -> [String: Any] {
    [
      "kind": kind, "id": payload["id"] ?? "library", "updated_at": stamp(5_000),
      "payload": payload,
    ]
  }

  /// A session record that lists only its first set, as when the last Finish never arrived.
  private func session(sets: [[String: Any]], end: TimeInterval) -> [String: Any] {
    record(
      "workout_session",
      [
        "id": push, "template_key": "push", "template_name": "Push", "started_at": stamp(0),
        "ended_at": stamp(end),
        "exercises": [["exercise_key": "bench", "exercise_name": "Bench press", "sets": sets]],
      ])
  }

  private func meal() -> [String: Any] {
    let item: [String: Any] = [
      "item_id": "oats", "name": "Oat Porridge", "source": "North Hall", "halls": ["North Hall"],
      "serving": "1 cup", "servings": 1, "confidence": 0.8, "rough": false,
      "kcal": ["low": 200, "high": 260], "protein_g": ["low": 6, "high": 9],
    ]
    return record(
      "meal",
      [
        "id": mealID.uuidString, "eaten_at": stamp(3_600), "day": "2027-01-15",
        "status": "confirmed", "edited": false, "in_health": true, "items": [item],
      ])
  }

  private func decode(_ records: [[String: Any]]) throws -> [SyncRecord] {
    let body = try JSONSerialization.data(withJSONObject: ["records": records, "next": NSNull()])
    return try JSONDecoder().decode(Restore.Page.self, from: body).records.compactMap(\.record)
  }

  private func serverRecords() throws -> [[String: Any]] {
    let bench = set(push, "Bench press", "bench", 60, at: 60, template: "push")
    return [
      session(sets: [bench], end: 120), bench,
      set(push, "Bench press", "bench", 65, at: 180, template: "push"),
      set(push, "Pull-up", "pull-up", nil, at: 300, template: "push"),
      set(pull, "Barbell row", "row", 45, at: 86_460, template: "pull"),
    ].map { $0["session_id"] == nil ? $0 : record("set", $0) } + [meal()]
  }

  /// Sets are the truth: grouped by session id, in logged order, with the session record's
  /// template and start and the later end; a session with sets and no record comes back too.
  /// Two pages of the fake GET /records are read until `next` is null.
  func testSessionsRebuiltFromSetRecords() async throws {
    let all = try serverRecords()
    let page = { (records: ArraySlice<[String: Any]>, next: String?) in
      VMResponse(
        status: 200,
        body: try JSONSerialization.data(
          withJSONObject: ["records": Array(records), "next": next.map { $0 as Any } ?? NSNull()]))
    }
    let fake = FakeVMTransport(routes: [
      "GET /records": try page(all[..<3], "p2"), "GET /records?after=p2": try page(all[3...], nil),
    ])
    let records = try await Restore.fetch(fake, kinds: "set,workout_session,meal")
    XCTAssertEqual(records.count, 6)
    let afters = await fake.sent.map { $0.query["after"] }
    XCTAssertEqual(afters, [nil, "p2"])

    let outcome = Restore.merge(
      records, library: TemplateLibrary(), finished: [], meals: [], at: start + 9_000)
    XCTAssertEqual(outcome.finished.count, 2)
    let first = outcome.finished[0]
    XCTAssertEqual(first.externalID, push)
    XCTAssertEqual(WorkoutFinish.externalID(for: first.session), push, "ids would not match")
    XCTAssertEqual(first.session.templateKey, "push")
    XCTAssertEqual(first.session.exercises.map(\.exercise), ["Bench press", "Pull-up"])
    XCTAssertEqual(first.session.sets(for: "Bench press")?.map(\.pounds), [60, 65])
    XCTAssertEqual(first.session.sets(for: "Pull-up")?.map(\.pounds), [nil])
    XCTAssertEqual(first.endedAt, start + 300, "the end is not the last set")
    XCTAssertTrue(first.inHealth, "a restored session would be written to Health again")
    let second = outcome.finished[1]
    XCTAssertEqual(second.session.templateKey, "pull", "no template from the sets")
    XCTAssertEqual(second.session.startedAt, start + 86_400)
    XCTAssertEqual(outcome.meals.map(\.items.first?.name), ["Oat Porridge"])
    XCTAssertEqual(outcome.meals.first?.items.first?.hall, "North Hall")
    XCTAssertEqual(outcome.meals.first?.items.first?.kcal, FoodRange(low: 200, high: 260))
    XCTAssertEqual(outcome.meals.first?.loggedAt, start + 3_600)
    XCTAssertEqual(outcome.text, "Restored 2 workouts, 1 meal")
  }

  /// A session record with no set records falls back to its own sets; nothing is re-sent.
  func testSessionWithoutSetRecordsUsesItsOwnSets() throws {
    let sets = [
      set(push, "Bench press", "bench", 60, at: 60, template: "push"),
      set(push, "Bench press", "bench", 65, at: 180, template: "push"),
    ]
    let outcome = Restore.merge(
      try decode([session(sets: sets, end: 200)]), library: TemplateLibrary(), finished: [],
      meals: [], at: start + 9_000)
    XCTAssertEqual(outcome.finished.first?.workingSets, 2)
    XCTAssertEqual(outcome.finished.first?.endedAt, start + 200)
    XCTAssertEqual(outcome.corrections, [])
  }

  /// A second restore changes nothing, and a newer local session, meal or program stays.
  func testRestoreIsIdempotentAndLocalNewerWins() throws {
    let records = try decode(try serverRecords() + [programRecord()])
    let once = Restore.merge(
      records, library: TemplateLibrary(), finished: [], meals: [], at: start + 9_000)
    XCTAssertNotNil(once.library)
    let twice = Restore.merge(
      records, library: try XCTUnwrap(once.library), finished: once.finished, meals: once.meals,
      at: start + 9_500)
    XCTAssertNil(twice.library, "the same program was applied again")
    XCTAssertEqual(twice.finished, once.finished)
    XCTAssertEqual(twice.meals, [])
    XCTAssertEqual(twice.corrections, [])
    XCTAssertEqual(twice.text, "Restored 0 workouts, 0 meals")

    var local = WorkoutSession(startedAt: start, templateKey: "push")
    local.logSet("Bench press", pounds: 70, reps: 5, at: start + 60)
    let newer = try XCTUnwrap(WorkoutFinish.close(local, at: start + 4_000))
    var library = TemplateLibrary()
    library.replaceProgram(
      with: [WorkoutTemplate(key: "mine", name: "Mine", exercises: [])], at: start + 6_000)
    let kept = Restore.merge(
      records, library: library, finished: [newer],
      meals: [LoggedMeal(id: mealID, loggedAt: start, items: [])], at: start + 9_000)
    XCTAssertNil(kept.library, "an older program replaced a newer local one")
    XCTAssertEqual(kept.finished.first, newer)
    XCTAssertEqual(kept.finished.count, 2, "the other session was not added")
    XCTAssertEqual(kept.meals, [])
  }

  /// A session rebuilt from more sets, or ending later, than its server record queues the
  /// corrected record, once; a matching record queues nothing.
  func testStaleSessionQueuesCorrectionOnce() throws {
    let records = try decode(try serverRecords())
    let once = Restore.merge(
      records, library: TemplateLibrary(), finished: [], meals: [], at: start + 9_000)
    XCTAssertEqual(once.corrections.map(\.kind), ["workout_session", "workout_session"])
    let fixed = try XCTUnwrap(once.corrections.first { $0.id == push }?.sessionPayload)
    XCTAssertEqual(fixed.exercises.map(\.sets.count), [2, 1])
    XCTAssertEqual(fixed.templateName, "Push")
    XCTAssertEqual(Restore.time(fixed.end), start + 300)
    let twice = Restore.merge(
      records, library: TemplateLibrary(), finished: once.finished, meals: once.meals,
      at: start + 9_500)
    XCTAssertEqual(twice.corrections, [], "a correction was queued twice")

    let bench = set(push, "Bench press", "bench", 60, at: 60, template: "push")
    let current = Restore.merge(
      try decode([session(sets: [bench], end: 120), record("set", bench)]),
      library: TemplateLibrary(), finished: [], meals: [], at: start + 9_000)
    XCTAssertEqual(current.finished.count, 1)
    XCTAssertEqual(current.corrections, [], "an up-to-date session was sent again")
  }

  private func programRecord() throws -> [String: Any] {
    let data = try JSONEncoder().encode(SyncRecord.program(library(), at: start + 5_000))
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["deleted"] = nil  // GET /records leaves it out
    return object
  }

  private func library() -> TemplateLibrary {
    var library = TemplateLibrary()
    library.upsert(WorkoutSeed(seedVersion: 3, templates: []))
    library.replaceProgram(with: [
      WorkoutTemplate(
        key: "push", name: "Push",
        exercises: [
          TemplateExercise(
            key: "bench", name: "Bench press", sets: 3, repsLow: 6, repsHigh: 10,
            restSeconds: 150, startPounds: 45)
        ]),
      WorkoutTemplate(key: "abs", name: "Abs", exercises: [], addOn: true),
    ])
    return library
  }

  /// The program goes out as seed_version and the templates in their own keys, add-on flags
  /// included, and comes back as the same library over the bundled seed.
  func testProgramRecordRoundTrips() throws {
    let sent = try programRecord()
    XCTAssertEqual(sent["kind"] as? String, "program")
    XCTAssertEqual(sent["id"] as? String, "library")
    let payload = try XCTUnwrap(sent["payload"] as? [String: Any])
    XCTAssertEqual(payload["seed_version"] as? Int, 3)
    let templates = try XCTUnwrap(payload["templates"] as? [[String: Any]])
    XCTAssertEqual(templates.map { $0["addOn"] as? Bool }, [false, true])
    let exercise = try XCTUnwrap((templates[0]["exercises"] as? [[String: Any]])?.first)
    XCTAssertEqual(exercise["repsLow"] as? Int, 6)
    XCTAssertNil(exercise["weightStep"], "a nil step is sent")

    var seed = TemplateLibrary()
    seed.upsert(WorkoutSeed(seedVersion: 1, templates: [.init(key: "a", name: "A", exercises: [])]))
    let outcome = Restore.merge(
      try decode([sent]), library: seed, finished: [], meals: [], at: start + 9_000)
    let restored = try XCTUnwrap(outcome.library)
    XCTAssertEqual(restored.templates, library().templates)
    XCTAssertTrue(restored.programImported)
    XCTAssertEqual(restored.programAt, start + 5_000)
    XCTAssertEqual(restored.next(after: nil)?.key, "push")
    XCTAssertEqual(outcome.text, "Restored program, 0 workouts, 0 meals")

    var older = library()
    older.replaceProgram(with: [.init(key: "old", name: "Old", exercises: [])], at: start)
    XCTAssertNotNil(
      Restore.merge(try decode([sent]), library: older, finished: [], meals: [], at: start).library,
      "an older local program was kept")
  }

  /// The Settings line from GET /records/summary.
  func testSummaryText() throws {
    let body = Data(
      (#"{"counts": {"program": 1, "set": 11, "workout_session": 2, "meal": 3, "visit": 28,"#
        + #" "my_place": 0, "location": 0, "weigh_in": 0}, "sessions_from_sets": 1}"#).utf8)
    XCTAssertEqual(
      try JSONDecoder().decode(RestoreSummary.self, from: body).text,
      "Program, 2 workouts (11 sets), 3 meals, 28 visits, 0 places")
  }

  /// S-058: a visit, a fix, a weigh-in and his place come back into their stores by id. The
  /// phone's own copy of a visit stays, nothing is queued, and a second restore adds nothing.
  /// His place names the restored visit; looked-up names are not records.
  func testVisitsWeighInsAndPlacesRestored() async throws {
    let visit = { (id: String, latitude: Double) -> [String: Any] in
      [
        "id": id, "day": "2027-01-15", "arrived_at": self.stamp(0),
        "departed_at": self.stamp(1_800),
        "latitude": latitude, "longitude": 20.5, "horizontal_accuracy_m": 20,
      ]
    }
    let records = try decode([
      record("visit", visit("visit.1", 10.5)), record("visit", visit("visit.2", 10.5)),
      record(
        "location",
        [
          "id": "location.1", "day": "2027-01-15", "at": stamp(600), "latitude": 10.5,
          "longitude": 20.5, "horizontal_accuracy_m": 50, "speed_mps": NSNull(),
        ]),
      record(
        "weigh_in",
        ["id": "W-1", "measured_at": stamp(60), "pounds": 172.4, "in_health": true]),
      record(
        "my_place",
        [
          "id": "P-1", "name": "Gym", "note": NSNull(), "latitude": 10.5, "longitude": 20.5,
          "radius_m": 100, "created_at": stamp(0),
        ]),
      meal(),
    ])
    let found = Restore.places(records)
    XCTAssertEqual(found.log.map(\.id), ["visit.1", "visit.2", "location.1"])
    XCTAssertEqual(found.weighIns.first?.measuredAt, start + 60)
    XCTAssertEqual(found.mine.first?.createdAt, start)

    let saves = Counter()
    var local = LocationLog()
    local.places = [
      PlaceRecord(
        id: "visit.1", day: "2027-01-15", arrivedAt: stamp(0), latitude: 40, longitude: 20.5,
        horizontalAccuracyM: 5)
    ]
    let recorder = LocationRecorder(log: local) { _ in saves.add() }
    let weighIns = WeighInStore { _ in saves.add() }
    let mine = MyPlacesStore { _ in saves.add() }
    var added = Restore.Places()
    added.log = await recorder.restore(found.log)
    added.weighIns = await weighIns.restore(found.weighIns)
    added.mine = await mine.restore(found.mine)
    XCTAssertEqual(added.log.map(\.id), ["visit.2", "location.1"], "the local visit.1 stays")
    XCTAssertEqual(added.text, ", 1 visit, 1 weigh-in, 1 place")
    let log = await recorder.log
    XCTAssertEqual(log.places.first { $0.id == "visit.1" }?.latitude, 40)
    XCTAssertEqual(log.places.count, 3)
    let weights = await weighIns.log.weighIns
    XCTAssertEqual(weights.map(\.pounds), [172.4])
    XCTAssertEqual(weights.first?.inHealth, true, "kept as Health took it, not written again")
    let places = await mine.places
    let named = try XCTUnwrap(log.places.first { $0.id == "visit.2" })
    XCTAssertEqual(places.name(named, looked: [:]), "Gym")
    XCTAssertEqual(saves.value, 3)

    let again = (
      await recorder.restore(found.log), await weighIns.restore(found.weighIns),
      await mine.restore(found.mine)
    )
    XCTAssertTrue(again.0.isEmpty && again.1.isEmpty && again.2.isEmpty, "\(again)")
    XCTAssertEqual(saves.value, 3, "a second restore wrote nothing")
    XCTAssertEqual(Restore.Places().text, "")
  }

  /// S-058: only an install with no finished workout, meal, visit or fix, and the bundled seed
  /// unchanged, is fresh; the offer needs records on the VM and comes once.
  func testFreshInstallDetection() async throws {
    var seed = TemplateLibrary()
    seed.upsert(WorkoutSeed(seedVersion: 3, templates: []))
    XCTAssertTrue(Restore.isFresh(finished: [], meals: [], log: LocationLog(), library: seed))
    XCTAssertFalse(Restore.isFresh(finished: [], meals: [], log: LocationLog(), library: library()))
    let workout = FinishedWorkout(
      session: WorkoutSession(startedAt: start), endedAt: start + 60, externalID: push,
      inHealth: true)
    XCTAssertFalse(
      Restore.isFresh(finished: [workout], meals: [], log: LocationLog(), library: seed))
    let meal = LoggedMeal(id: mealID, loggedAt: start, items: [])
    XCTAssertFalse(Restore.isFresh(finished: [], meals: [meal], log: LocationLog(), library: seed))
    var log = LocationLog()
    _ = log.apply(
      .fix(at: start, latitude: 10, longitude: 20, accuracy: 5, speed: nil), at: start)
    XCTAssertFalse(Restore.isFresh(finished: [], meals: [], log: log, library: seed))

    let summary = { (counts: String) in
      try JSONDecoder().decode(
        RestoreSummary.self, from: Data(#"{"counts": {\#(counts)}, "sessions_from_sets": 0}"#.utf8))
    }
    XCTAssertFalse(try summary(#""visit": 0, "meal": 0"#).hasRecords)
    XCTAssertTrue(try summary(#""visit": 2, "meal": 0"#).hasRecords)

    let saved = Counter()
    let sync = HealthSync(state: SyncState()) { _ in saved.add() }
    let first = await sync.offerRestore()
    let second = await sync.offerRestore()
    XCTAssertEqual([first, second], [true, false])
    XCTAssertEqual(saved.value, 1)
  }
}

/// Counts saves from a store's `@Sendable` callback.
private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  var value: Int { lock.withLock { count } }
  func add() { lock.withLock { count += 1 } }
}
