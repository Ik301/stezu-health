import Foundation
import StezuCore

/// Core results the home screen shows. Each one is nil until it exists (absent, not zero).
struct HomeInputs: Sendable, Equatable {
  var trend: TrendEstimate?
  var target: WeeklyTargetDecision?
  /// Today's logged intake in kcal, nil when nothing is logged yet.
  var intakeTodayKcal: Double?
  var protein: ProteinFloor.Outcome?
  var lastSession: LastSessionNumbers?
}

/// Builds the Data, Food and Workout cards and picks the inverted one from an injected clock.
struct HomeViewModel: Sendable {
  static let missing = "--"

  /// Start hour and card id; a card stays inverted until the next start. Hours before the
  /// first start belong to the last entry. These are defaults, not personal numbers.
  static let defaultSchedule: [(hour: Int, cardID: String)] = [
    (5, "data"), (11, "food"), (16, "workout"), (20, "food"),
  ]

  var calendar: Calendar = .current
  var schedule: [(hour: Int, cardID: String)] = HomeViewModel.defaultSchedule
  var now: @Sendable () -> Date = { Date() }

  func cards(_ inputs: HomeInputs) -> [HomeCard] {
    [dataCard(inputs), foodCard(inputs), workoutCard(inputs)]
  }

  /// The id of the "log this now" card for the clock's current hour.
  func invertedCardID() -> String? {
    let hour = calendar.component(.hour, from: now())
    let sorted = schedule.sorted { $0.hour < $1.hour }
    return (sorted.last { $0.hour <= hour } ?? sorted.last)?.cardID
  }

  private func dataCard(_ inputs: HomeInputs) -> HomeCard {
    HomeCard(
      id: "data", label: "Data", subtitle: "Trend weight, lb",
      value: inputs.trend.map { String(format: "%.1f", $0.trend) } ?? Self.missing,
      confidence: inputs.trend?.confidence)
  }

  private func foodCard(_ inputs: HomeInputs) -> HomeCard {
    let intake = inputs.intakeTodayKcal.map { Self.number($0, digits: 0) }
    let target = inputs.target.map { Self.number($0.newTarget, digits: 0) }
    let value =
      intake == nil && target == nil
      ? Self.missing : "\(intake ?? Self.missing) / \(target ?? Self.missing)"
    var subtitle = "Today, kcal of target"
    if case .evaluated(let check) = inputs.protein, check.isUnderFloor {
      subtitle += ", protein low"
    }
    return HomeCard(
      id: "food", label: "Food", subtitle: subtitle, value: value,
      confidence: inputs.target?.confidence)
  }

  private func workoutCard(_ inputs: HomeInputs) -> HomeCard {
    guard let last = inputs.lastSession, let top = Self.topSet(last.sets) else {
      return HomeCard(
        id: "workout", label: "Workout", subtitle: "Last session", value: Self.missing)
    }
    let value =
      top.pounds.map { "\(Self.number($0, digits: 1)) x \(top.reps)" } ?? "\(top.reps) reps"
    return HomeCard(
      id: "workout", label: "Workout", subtitle: "\(last.exercise), \(last.daysAgo)d ago",
      value: value, confidence: last.confidence)
  }

  /// The heaviest set, then the most reps. Bodyweight sets (nil pounds) rank below loaded ones.
  private static func topSet(_ sets: [WorkoutSet]) -> WorkoutSet? {
    sets.max { ($0.pounds ?? -1, $0.reps) < ($1.pounds ?? -1, $1.reps) }
  }

  /// Fixed-point text that drops a trailing ".0", independent of the device locale.
  private static func number(_ value: Double, digits: Int) -> String {
    let text = String(format: "%.\(digits)f", value)
    return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
  }
}
