import Foundation

/// Double progression: add reps inside a rep range, then add weight once every working set
/// reaches the top of the range, and start again at the bottom.
public enum DoubleProgression {
  /// Settings for the rule. The defaults are common textbook values, not personal numbers.
  public struct Config: Sendable, Equatable {
    public let repRange: ClosedRange<Int>
    /// Pounds added when every working set hit the top of the range.
    public let weightStepPounds: Double

    /// Nil when the range starts below 1 rep or the step is not a positive finite number.
    public init?(repRange: ClosedRange<Int> = 8...12, weightStepPounds: Double = 5) {
      guard repRange.lowerBound >= 1, weightStepPounds.isFinite, weightStepPounds > 0 else {
        return nil
      }
      self.repRange = repRange
      self.weightStepPounds = weightStepPounds
    }
  }

  public enum Action: Sendable, Equatable {
    case addReps
    case addWeight
  }

  /// What to try next time for one exercise.
  public struct Suggestion: Sendable, Equatable {
    public let exercise: String
    public let action: Action
    /// Weight for every working set; nil means bodyweight.
    public let pounds: Double?
    /// Target reps, one per working set, in log order.
    public let reps: [Int]
    /// Inherited from the last session's numbers: old numbers make a weaker suggestion.
    public let confidence: Confidence
  }

  /// The suggestion for next time, or nil when there is no last session (absent, not zero).
  ///
  /// Working sets are the sets at the heaviest weight of the last session; lighter sets
  /// (warm-ups) are ignored. A bodyweight exercise at the top of the range gets its first
  /// added load of one weight step.
  public static func suggest(after last: LastSessionNumbers?, config: Config) -> Suggestion? {
    guard let last, !last.sets.isEmpty else { return nil }
    let heaviest = last.sets.compactMap(\.pounds).max()
    let working = last.sets.filter { $0.pounds == heaviest }
    let top = config.repRange.upperBound

    if working.allSatisfy({ $0.reps >= top }) {
      return Suggestion(
        exercise: last.exercise, action: .addWeight,
        pounds: (heaviest ?? 0) + config.weightStepPounds,
        reps: Array(repeating: config.repRange.lowerBound, count: working.count),
        confidence: Confidence(
          level: last.confidence.level,
          reason: "all \(working.count) working sets hit \(top) reps; \(last.confidence.reason)"))
    }
    let below = working.filter { $0.reps < top }.count
    return Suggestion(
      exercise: last.exercise, action: .addReps, pounds: heaviest,
      reps: working.map { $0.reps >= top ? top : $0.reps + 1 },
      confidence: Confidence(
        level: last.confidence.level,
        reason: "\(below) of \(working.count) working sets under \(top) reps; "
          + last.confidence.reason))
  }
}
