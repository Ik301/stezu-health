import Foundation
import StezuCore

/// Synthetic server answers for `-uitest` launches, keyed by route ("POST /scan"). Each story that
/// calls the server adds its routes here. Every value is made up (D-034).
enum UITestFixtures {
  static let vmRoutes: [String: VMResponse] = [
    "GET /health": VMResponse(
      status: 200, body: Data(#"{"status": "ok", "version": "0.1.0"}"#.utf8)),
    "POST /scan": VMResponse(status: 200, body: Data(scanReply.utf8)),
  ]

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
