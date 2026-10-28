import Foundation
import StezuCore

/// Synthetic server answers for `-uitest` launches, keyed by route ("POST /scan"). Each story that
/// calls the server adds its routes here. Every value is made up (D-034).
enum UITestFixtures {
  static let vmRoutes: [String: VMResponse] = [
    "GET /health": VMResponse(
      status: 200, body: Data(#"{"status": "ok", "version": "0.1.0"}"#.utf8)),
    "POST /scan": VMResponse(status: 200, body: Data(scanReply.utf8)),
    "GET /search": VMResponse(status: 200, body: Data(searchReply.utf8)),
    "GET /search?estimate=true": VMResponse(status: 200, body: Data(estimateReply.utf8)),
    "POST /sync": VMResponse(status: 200, body: Data(#"{"accepted": 3, "rejected": 0}"#.utf8)),
    "GET /sync/status": VMResponse(status: 200, body: Data(#"{"samples_total": 3}"#.utf8)),
    "GET /barcode/0000000000031": VMResponse(status: 200, body: Data(barcodeReply.utf8)),
    "GET /barcode/0000000000024": VMResponse(
      status: 200, body: Data(#"{"status": "not_found", "gtin": "0000000000024"}"#.utf8)),
  ]

  /// Barcode mode's synthetic code (S-016): a made-up product, or in "barcode-unknown" a code
  /// Open Food Facts does not know.
  static func barcode(scenario: String?) -> String {
    scenario == "barcode-unknown" ? "0000000000024" : "0000000000031"
  }
  static let barcodeReply = #"""
    {"status": "found", "source": "open_food_facts", "gtin": "0000000000031",
     "name": "Oat Bar", "brand": "Example Foods",
     "per_serving": {"label": "1 bar (40 g)", "quantity": 40, "unit": "g", "kcal": 160,
      "protein_g": 4}, "per_package": null, "per_100": null, "cached": false}
    """#

  /// "sync": three made-up heart-rate readings to send; the fake status above counts three.
  static func healthChanges(scenario: String?) -> [HealthType: [HealthChange]] {
    guard scenario == "sync" || scenario == BackgroundSync.scenario else { return [:] }
    let time = SyncSample.timestamp(Date())
    let type = "HKQuantityTypeIdentifierHeartRate"
    let sample = { (n: Int) -> HealthChange in
      .added(
        SyncSample(
          uuid: "SYNTHETIC-\(n)", type: type, start: time, end: time, value: Double(60 + n),
          unit: "count/min", sourceName: "Example Watch", sourceBundle: nil))
    }
    return [.heartRate: (1...3).map(sample)]
  }

  /// Past sessions for a scenario, dated back from `now`. "workout-history": a Day 1 session
  /// 7 days ago and a newer Day 2 session that also has bench press and the only overhead press.
  static func workoutHistory(scenario: String?, now: Date = Date()) -> [WorkoutSession] {
    if isFoodWeek(scenario) { return foodWeekSessions() }
    guard scenario == "workout-history" else { return [] }
    func session(_ key: String, daysAgo: Int, _ sets: [(String, Double?, Int)]) -> WorkoutSession {
      let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
      var session = WorkoutSession(startedAt: start, templateKey: key)
      for (index, set) in sets.enumerated() {
        session.logSet(set.0, pounds: set.1, reps: set.2, at: start + Double(index + 1) * 120)
      }
      return session
    }
    return [
      session(
        "day-1", daysAgo: 7,
        [("Bench press", 60, 8), ("Bench press", 60, 8), ("Bench press", 60, 7)]
      ),
      session(
        "day-2", daysAgo: 2,
        [("Bench press", 65, 5), ("Overhead press", 40, 10), ("Barbell row", 70, 8)]),
    ]
  }

  /// POST /scan answers only in these scenarios ("sync-meals": S-029 logs the fixture match);
  /// otherwise it is held and "Matching..." stays.
  static let photoMatchScenario = "photo-match"
  static func heldRoutes(scenario: String?) -> Set<String> {
    scenario == photoMatchScenario || scenario == "sync-meals" ? [] : ["POST /scan"]
  }

  /// "data-week": Data is already connected and the clock is Sunday 2026-01-11, noon. Stezu
  /// weighed in on 5 of the week's 7 days (Mon, Tue, Wed, Fri, Sat) and 3 days the week before;
  /// a strap's profile weight on Thursday must not count. All weights are made up.
  static let dataWeekScenario = "data-week"
  static func clock(scenario: String?) -> @Sendable () -> Date {
    guard isDataWeek(scenario) else { return { Date() } }
    let sunday = dataWeekDay(11)
    return { sunday }
  }
  static func healthSamples(scenario: String?) -> [HealthSample] {
    guard isDataWeek(scenario) else { return [] }
    let stezu: [(Int, Double)] = [
      (-3, 171.2), (-1, 171.0), (2, 170.8), (5, 170.6), (6, 170.4), (7, 170.5), (9, 170.0),
      (10, 169.8),
    ]
    return stezu.map {
      HealthSample(
        type: .bodyMass, date: dataWeekDay($0.0, hour: 7), sourceName: "Stezu",
        sourceBundleID: WeeklyWeight.stezuBundleID, value: $0.1)
    } + [
      HealthSample(
        type: .bodyMass, date: dataWeekDay(8, hour: 7), sourceName: "Strap",
        sourceBundleID: "example.strap", value: 150.0)
    ]
  }

  /// "data-week" context (S-022), all made up: steps Mon to Sat in two halves (mean 7333) plus
  /// the Saturday before, HRV on 5 days (median 47 ms), resting HR on 5 days (mean 59 bpm), and
  /// 5 nights (ending Mon, Tue, Wed, Fri, Sat) of 7h 20m asleep among in-bed and awake stages.
  static func weekHealthSamples(scenario: String?) -> [HealthSample] {
    guard isDataWeek(scenario) else { return [] }
    let steps: [Int: Double] = [3: 6000, 5: 4000, 6: 3250, 7: 3600, 8: 4550, 9: 2700, 10: 3900]
    let rows: [(HealthType, Int, [Int: Double])] = [
      (.stepCount, 9, steps), (.stepCount, 18, steps),
      (.heartRateVariability, 6, [5: 38, 6: 61, 7: 47, 8: 55, 9: 42]),
      (.restingHeartRate, 8, [5: 58, 6: 60, 7: 57, 9: 59, 10: 61]),
    ]
    return rows.flatMap { type, hour, days in
      days.map {
        HealthSample(
          type: type, date: dataWeekDay($0.key, hour: hour), sourceName: "Phone", value: $0.value)
      }
    }
  }
  static func sleep(scenario: String?) -> [SleepInterval] {
    guard isDataWeek(scenario) else { return [] }
    let stages: [(SleepStage, Double, Double)] = [
      (.inBed, -60, 420), (.asleepCore, -45, 180), (.asleepDeep, 180, 240),
      (.asleepREM, 240, 330), (.awake, 330, 340), (.asleepCore, 340, 405),
    ]
    // "home-week" (S-037) adds last night, ending Sunday: 6h 15m asleep, two wake-ups (S-040).
    let lastNight: [(SleepStage, Double, Double)] = [
      (.inBed, -60, 420), (.asleepCore, -30, 180), (.asleepDeep, 180, 240), (.awake, 240, 250),
      (.asleepREM, 250, 300), (.awake, 300, 305), (.asleepREM, 305, 360),
    ]
    let nights: [(Int, [(SleepStage, Double, Double)])] =
      [5, 6, 7, 9, 10].map { ($0, stages) }
      + (scenario == homeWeekScenario ? [(11, lastNight)] : [])
    return nights.flatMap { day, stages in
      stages.map {
        let midnight = dataWeekDay(day, hour: 0)
        return (start: midnight + $0.1 * 60, end: midnight + $0.2 * 60, stage: $0.0)
      }
    }
  }

  /// "data-week" strap context (S-027), all made up: blood oxygen on 6 days (fractions, median
  /// 97%), respiratory rate on 5 nights (median 14.4 br/min), body temperature on 4 nights
  /// (median 97.8 °F), all from a strap; no wrist temperature.
  static func strapSamples(scenario: String?) -> [HealthSample] {
    guard scenario == dataWeekScenario else { return [] }
    let rows: [(HealthType, Int, [Int: Double])] = [
      (.oxygenSaturation, 4, [5: 0.97, 6: 0.95, 7: 0.98, 8: 0.96, 9: 0.97, 10: 0.99]),
      (.respiratoryRate, 3, [5: 14.2, 6: 15.0, 7: 14.6, 9: 13.8, 10: 14.4]),
      (.bodyTemperature, 3, [5: 97.7, 6: 97.9, 8: 98.1, 10: 97.5]),
    ]
    return rows.flatMap { type, hour, days in
      days.map {
        HealthSample(
          type: type, date: dataWeekDay($0.key, hour: hour), sourceName: "Strap",
          sourceBundleID: "example.strap", value: $0.value)
      }
    }
  }

  /// "data-food-week" (S-023): data-week's connection, Sunday clock, weigh-ins, steps, HRV,
  /// resting HR and sleep, plus logged meals and sessions, so Monday has every kind of record
  /// (S-025). All made up.
  static let foodWeekScenario = "data-food-week"
  /// "home-week" (S-026): data-food-week plus two meals today (Sunday), for the Home cards.
  static let homeWeekScenario = "home-week"
  static func isDataWeek(_ scenario: String?) -> Bool {
    scenario == dataWeekScenario || isFoodWeek(scenario)
  }
  static func isFoodWeek(_ scenario: String?) -> Bool {
    scenario == foodWeekScenario || scenario == homeWeekScenario
  }

  /// Meal A every logged day (Mon, Tue, Wed, Fri, Sat) and meal B on Mon, Wed and Sat: a mean of
  /// 1000-1320 kcal and 52-68 g protein over 5 days. The Sunday before must not count.
  static func loggedMeals(scenario: String?) -> [LoggedMeal] {
    guard isFoodWeek(scenario) else { return [] }
    func meal(_ day: Int, _ kcal: (Int, Int), _ protein: (Int, Int)) -> LoggedMeal {
      let reply = #"""
        {"meal_id": "fixture", "items": [{"item_id": "x", "name": "Grain Bowl", "servings": 1,
         "kcal": {"low": \#(kcal.0), "high": \#(kcal.1)},
         "protein_g": {"low": \#(protein.0), "high": \#(protein.1)}}]}
        """#
      let items = (try? PhotoMatchClient.decode(Data(reply.utf8)).items) ?? []
      return LoggedMeal(id: UUID(), loggedAt: dataWeekDay(day, hour: 12), items: items)
    }
    let today = scenario == homeWeekScenario ? [11] : []  // 1200-1600 kcal, 60-80 g protein
    return ([5, 6, 7, 9, 10, 4] + today).map { meal($0, (700, 900), (40, 50)) }
      + ([5, 7, 10] + today).map { meal($0, (500, 700), (20, 30)) }
  }

  /// Stezu sessions Monday (3 sets) and Thursday (2 sets) at 18:00, one the Saturday before.
  static func foodWeekSessions() -> [WorkoutSession] {
    [(5, 3), (8, 2), (3, 1)].map { day, sets in
      var session = WorkoutSession(startedAt: dataWeekDay(day, hour: 18), templateKey: "day-1")
      for index in 0..<sets {
        session.logSet(
          "Bench press", pounds: 60, reps: 8, at: session.startedAt + Double(index + 1) * 120)
      }
      return session
    }
  }

  /// Health's workouts: Finish's copy of Monday's session and a Saturday run from a watch.
  static func foodWeekWorkouts(scenario: String?) -> [HealthSample] {
    guard isFoodWeek(scenario) else { return [] }
    return [
      HealthSample(
        type: .workout, date: dataWeekDay(5, hour: 18), sourceName: "Stezu",
        sourceBundleID: WeeklyWeight.stezuBundleID),
      HealthSample(
        type: .workout, date: dataWeekDay(10, hour: 9), sourceName: "Example Watch",
        sourceBundleID: "example.watch"),
    ]
  }

  /// "food-history" (S-019), all made up: today a yogurt at 8:00 and a two-dish lunch at 12:30
  /// (330-450 kcal, 20-27 g protein in all); yesterday a burrito at 19:00 and a photo pending.
  static func foodHistory(scenario: String?) -> (logged: [LoggedMeal], pending: [CapturedMeal]) {
    guard scenario == "food-history" else { return ([], []) }
    let today = Calendar.current.startOfDay(for: Date())
    func meal(_ hours: Double, _ items: [(String, String, [Int])]) -> LoggedMeal {
      let json = items.map { name, source, r in
        #"{"item_id": "\#(name)", "name": "\#(name)", \#(source), "servings": 1, "kcal": {"#
          + #""low": \#(r[0]), "high": \#(r[1])}, "protein_g": {"low": \#(r[2]), "high": \#(r[3])}}"#
      }
      let reply = #"{"meal_id": "fixture", "items": ["# + json.joined(separator: ",") + "]}"
      let decoded = (try? PhotoMatchClient.decode(Data(reply.utf8)).items) ?? []
      return LoggedMeal(id: UUID(), loggedAt: today + hours * 3600, items: decoded)
    }
    let (north, south) = (#""hall": "North Hall""#, #""hall": "South Hall""#)
    return (
      [
        meal(8, [("Plain Yogurt", #""brand": "Example Dairy""#, [90, 110, 14, 18])]),
        meal(
          12.5,
          [("Herb Rice", north, [160, 220, 4, 6]), ("Roast Vegetables", south, [80, 120, 2, 3])]),
        meal(-5, [("Bean Burrito", #""brand": "Example Grill""#, [360, 440, 10, 14])]),
      ], [CapturedMeal(id: UUID(), capturedAt: today - 17 * 3600)]
    )
  }

  /// "location" (S-032): two visits, one arriving then departing, and a fix; synthetic (D-034).
  static func locations(scenario: String?, now: Date = Date()) -> [LocationEvent] {
    guard scenario == "location" else { return [] }
    let base = max(Calendar.current.startOfDay(for: now), now - 3600)
    let at = { (n: Double) in base + n * now.timeIntervalSince(base) / 6 }
    return [
      .visit(arrival: at(1), departure: nil, latitude: 10.25, longitude: -30.5, accuracy: 40),
      .visit(arrival: at(1), departure: at(2), latitude: 10.25, longitude: -30.5, accuracy: 35),
      .fix(at: at(3), latitude: 10.5, longitude: -30.25, accuracy: 500, speed: nil),
      .visit(arrival: at(4), departure: at(5), latitude: 10.75, longitude: -30, accuracy: 50),
    ]
  }

  /// "background-sync" (S-033): a visit queued as if recorded while the app was closed.
  static func backgroundVisit(now: Date = Date()) -> LocationEvent {
    .visit(arrival: now - 1800, departure: nil, latitude: 10.25, longitude: -30.5, accuracy: 40)
  }

  /// "rotation" (S-036, with -uitest-persist): the store's last finished session is Day 1, two
  /// days ago, too old to continue. Made-up numbers.
  static let rotationScenario = "rotation"
  static func rotationFinished(now: Date = Date()) -> [FinishedWorkout] {
    var session = WorkoutSession(startedAt: now - 2 * 86_400, templateKey: "day-1")
    session.logSet("Bench press", pounds: 60, reps: 8, at: session.startedAt + 120)
    session.logSet("Bench press", pounds: 60, reps: 8, at: session.startedAt + 300)
    return [WorkoutFinish.close(session, at: session.startedAt + 1800)].compactMap { $0 }
  }

  /// A day of January 2026 (0 and below roll back into December) in the device's calendar.
  private static func dataWeekDay(_ day: Int, hour: Int = 12) -> Date {
    let first = Calendar.current.date(
      from: DateComponents(year: 2026, month: 1, day: 1, hour: hour))!
    return Calendar.current.date(byAdding: .day, value: day - 1, to: first)!
  }

  /// Two dishes from two made-up halls and one item on no menu (rough, wider range).
  static let scanReply = #"""
    {"meal_id": "fixture", "items": [
     {"item_id": "01-L-1", "name": "Herb Rice", "hall": "North Hall", "serving": "4 oz",
      "servings": 1.5, "confidence": 0.9, "kcal": {"low": 230, "high": 310},
      "protein_g": {"low": 4, "high": 6}},
     {"item_id": "02-L-7", "name": "Roast Vegetables", "hall": "South Hall", "serving": "1/2 cup",
      "servings": 1, "confidence": 0.75, "kcal": {"low": 80, "high": 120},
      "protein_g": {"low": 2, "high": 3}},
     {"item_id": "unlisted", "name": "Brownie", "hall": null, "servings": 1, "confidence": 0.4,
      "rough": true, "kcal": {"low": 150, "high": 350}, "protein_g": {"low": 1, "high": 4}}]}
    """#

  /// GET /search for any text (S-014): one dish at two made-up halls, one restaurant dish, one
  /// packaged food. The text estimate answers only with estimate=true.
  static let searchReply = #"""
    {"q": "rice", "date": "2026-01-05", "meal": null, "groups": [
     {"source": "dining", "status": "ok", "results": [
      {"id": "01-L-1", "name": "Herb Rice", "hall": "North Hall", "meal": "Lunch",
       "serving": "4 oz", "kcal": 160, "protein_g": 4, "halls": ["North Hall", "South Hall"]}]},
     {"source": "open_food_facts", "status": "ok", "results": [
      {"gtin": "0000000000017", "name": "Plain Yogurt", "brand": "Example Dairy",
       "per_serving": {"label": "1 cup", "kcal": 100, "protein_g": 16}}]},
     {"source": "usda_fdc", "status": "ok", "results": [
      {"fdc_id": 1, "name": "Bean burrito, restaurant", "brand": null,
       "per_serving": {"label": "1 burrito", "kcal": 400, "protein_g": 12}}]},
     {"source": "estimate", "status": "available", "results": []}]}
    """#
  static let estimateReply = #"""
    {"q": "noodle bowl", "date": "2026-01-05", "meal": null, "groups": [
     {"source": "estimate", "status": "ok", "results": [
      {"name": "Noodle Bowl", "portion": "1 bowl", "rough": true,
       "kcal": {"low": 420, "high": 980}, "protein_g": {"low": 12, "high": 28}}]}]}
    """#
}
