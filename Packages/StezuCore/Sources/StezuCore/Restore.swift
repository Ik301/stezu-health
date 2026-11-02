import Foundation

/// The library as one `program` record, id "library" (S-057), templates in their Codable keys.
public struct ProgramRecord: Codable, Sendable, Equatable {
  public let seedVersion: Int?
  public let templates: [WorkoutTemplate]
  enum CodingKeys: String, CodingKey {
    case templates
    case seedVersion = "seed_version"
  }
}

extension SyncRecord {
  /// The whole library after an import, stamped `at`.
  public static func program(_ library: TemplateLibrary, at date: Date) -> SyncRecord {
    SyncRecord(
      kind: "program", id: "library", updatedAt: stamp(date, .current), deleted: false,
      payload: nil,
      programPayload: .init(seedVersion: library.seedVersion, templates: library.templates))
  }
}

/// What GET /records/summary says the VM holds.
public struct RestoreSummary: Decodable, Sendable, Equatable {
  public let counts: [String: Int]
  public let sessionsFromSets: Int?
  enum CodingKeys: String, CodingKey {
    case counts
    case sessionsFromSets = "sessions_from_sets"
  }

  /// "Program, 2 workouts (11 sets), 3 meals, 28 visits, 0 places"; sessions without sets count.
  public var text: String {
    let n = { (kind: String) in counts[kind] ?? 0 }
    let workouts = max(sessionsFromSets ?? 0, n("workout_session"))
    return [
      n("program") > 0 ? "Program" : "No program",
      "\(Restore.count(workouts, "workout")) (\(Restore.count(n("set"), "set")))",
      Restore.count(n("meal"), "meal"), Restore.count(n("visit"), "visit"),
      Restore.count(n("my_place"), "place"),
    ].joined(separator: ", ")
  }
}

/// S-057 (D-143): the VM's records merged back by id. Nothing local is deleted, the newer local
/// copy wins, nothing goes to Health, and only a lagging session summary is queued again.
public enum Restore {
  /// What a merge changes: `library` is nil when the local one stays, `meals` are only new ones.
  public struct Outcome: Sendable, Equatable {
    public var library: TemplateLibrary?
    public var finished: [FinishedWorkout]
    public var meals: [LoggedMeal]
    public var corrections: [SyncRecord]
    public var text: String
  }

  struct Page: Decodable {
    struct Lossy: Decodable {  // one odd record is skipped, not the whole page
      let record: SyncRecord?
      init(from decoder: any Decoder) throws { record = try? SyncRecord(from: decoder) }
    }
    let records: [Lossy]
    let next: String?
  }

  /// Every page of GET /records for `kinds`, until `next` is null.
  public static func fetch(_ transport: any VMTransport, kinds: String) async throws
    -> [SyncRecord]
  {
    var (records, after): ([SyncRecord], String?) = ([], nil)
    repeat {
      var query = ["kinds": kinds, "limit": "500"]
      query["after"] = after
      let reply = try await transport.send(VMRequest(path: "/records", query: query))
      guard reply.status == 200 else { throw VMTransportError.unreachable("\(reply.status)") }
      let page = try JSONDecoder().decode(Page.self, from: reply.body)
      (records, after) = (records + page.records.compactMap(\.record), page.next)
    } while after != nil
    return records
  }

  public static func merge(
    _ records: [SyncRecord], library: TemplateLibrary, finished: [FinishedWorkout],
    meals: [LoggedMeal], at date: Date
  ) -> Outcome {
    var outcome = Outcome(library: nil, finished: finished, meals: [], corrections: [], text: "")
    if let record = records.first(where: { $0.kind == "program" }),
      let program = record.programPayload, let at = time(record.updatedAt),
      !library.programImported || library.programAt ?? .distantPast < at
    {
      var updated = library
      updated.replaceProgram(with: program.templates, at: at)
      outcome.library = updated
    }
    let sets = Dictionary(grouping: records.compactMap(\.setPayload), by: \.sessionId)
    let summaries = Dictionary(
      records.compactMap { r in r.sessionPayload.map { (r.id, $0) } },
      uniquingKeysWith: { a, _ in a })
    var restored = 0
    for id in Set(sets.keys).union(summaries.keys).sorted() {
      let (own, summary) = (sets[id] ?? [], summaries[id])
      let used = own.isEmpty ? summary?.exercises.flatMap(\.sets) ?? [] : own
      guard let workout = rebuild(id, sets: used, summary: summary) else { continue }
      if let local = outcome.finished.firstIndex(where: { $0.externalID == id }) {
        guard outcome.finished[local].endedAt < workout.endedAt else { continue }
        outcome.finished[local] = workout
      } else {
        outcome.finished.append(workout)
      }
      restored += 1
      let sent = summary?.exercises.reduce(0) { $0 + $1.sets.count } ?? 0
      guard !own.isEmpty,
        sent < workout.workingSets
          || summary.flatMap({ time($0.end) }) ?? .distantPast < workout.endedAt
      else { continue }
      let keys = Dictionary(
        own.compactMap { s in s.exerciseKey.map { (s.exercise, $0) } },
        uniquingKeysWith: { a, _ in a })
      outcome.corrections.append(
        .session(workout, templateName: summary?.templateName, keys: keys, at: date))
    }
    outcome.finished.sort { $0.session.startedAt < $1.session.startedAt }
    outcome.meals = records.compactMap { r in
      guard r.kind == "meal", let m = r.payload, let id = UUID(uuidString: r.id),
        let at = time(m.eatenAt),
        !meals.contains(where: { $0.id == id })
      else { return nil }
      var meal = LoggedMeal(id: id, loggedAt: at, items: m.items.map(\.matched))
      meal.inHealth = m.inHealth
      return meal
    }
    outcome.text =
      "Restored " + (outcome.library == nil ? "" : "program, ") + count(restored, "workout")
      + ", " + count(outcome.meals.count, "meal")
    return outcome
  }

  /// A session from its sets; its record gives template and start, the end is the later one.
  static func rebuild(_ id: String, sets: [SetRecord], summary: SessionRecord?) -> FinishedWorkout?
  {
    let timed = sets.compactMap { s in time(s.loggedAt).map { (s, $0) } }.sorted { $0.1 < $1.1 }
    guard let first = timed.first, let last = timed.last?.1 else { return nil }
    let millis = Double(id.split(separator: ".").last ?? "").map { $0 / 1000 }
    var session = WorkoutSession(
      startedAt: summary.flatMap { time($0.start) } ?? millis.map(Date.init(timeIntervalSince1970:))
        ?? first.1, templateKey: summary?.templateKey ?? first.0.templateKey)
    for (s, at) in timed { session.logSet(s.exercise, pounds: s.pounds, reps: s.reps, at: at) }
    let end = max(summary.flatMap { time($0.end) } ?? last, last)
    return FinishedWorkout(session: session, endedAt: end, externalID: id, inHealth: true)
  }

  static func time(_ text: String) -> Date? {
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return format.date(from: text) ?? ISO8601DateFormatter().date(from: text)
  }

  static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
}

extension MealRecord.Item {
  /// Back to the item the phone logged: the source is a hall when the halls list it, else a brand.
  var matched: MatchedItem {
    let hall = halls?.contains(source ?? "") == true ? source : nil
    return MatchedItem(
      itemId: itemId, name: name, hall: hall, halls: halls,
      brand: hall == nil && source != "estimate" ? source : nil, serving: serving,
      servings: servings, confidence: confidence, rough: rough, kcal: kcal, proteinG: proteinG)
  }
}
