import Foundation
import StezuCore

/// Synthetic server answers for `-uitest` launches, keyed by route ("POST /scan"). Each story that
/// calls the server adds its routes here. Every value is made up (D-034).
enum UITestFixtures {
  static let vmRoutes: [String: VMResponse] = [
    "GET /health": VMResponse(
      status: 200, body: Data(#"{"status": "ok", "version": "0.1.0"}"#.utf8)),
    "POST /scan": VMResponse(status: 200, body: Data(scanReply.utf8)),
    "POST /sync": VMResponse(status: 200, body: Data(#"{"accepted": 3, "rejected": 0}"#.utf8)),
    "GET /sync/status": VMResponse(status: 200, body: Data(#"{"samples_total": 3}"#.utf8)),
  ]

  /// "sync": three made-up heart-rate readings to send; the fake status above counts three.
  static func healthChanges(scenario: String?) -> [HealthType: [HealthChange]] {
    guard scenario == "sync" else { return [:] }
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

  /// POST /scan answers only in this scenario; otherwise it is held and "Matching..." stays.
  static let photoMatchScenario = "photo-match"
  static func heldRoutes(scenario: String?) -> Set<String> {
    scenario == photoMatchScenario ? [] : ["POST /scan"]
  }

  /// "data-week": Data is already connected and the clock is Sunday 2026-01-11, noon. Stezu
  /// weighed in on 5 of the week's 7 days (Mon, Tue, Wed, Fri, Sat) and 3 days the week before;
  /// a strap's profile weight on Thursday must not count. All weights are made up.
  static let dataWeekScenario = "data-week"
  static func clock(scenario: String?) -> @Sendable () -> Date {
    guard scenario == dataWeekScenario else { return { Date() } }
    let sunday = dataWeekDay(11)
    return { sunday }
  }
  static func healthSamples(scenario: String?) -> [HealthSample] {
    guard scenario == dataWeekScenario else { return [] }
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
    guard scenario == dataWeekScenario else { return [] }
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
    guard scenario == dataWeekScenario else { return [] }
    let stages: [(SleepStage, Double, Double)] = [
      (.inBed, -60, 420), (.asleepCore, -45, 180), (.asleepDeep, 180, 240),
      (.asleepREM, 240, 330), (.awake, 330, 340), (.asleepCore, 340, 405),
    ]
    return [5, 6, 7, 9, 10].flatMap { day in
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
}
