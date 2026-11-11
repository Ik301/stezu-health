import Foundation

/// The sets and rep range chosen for an added exercise in Sets and reps (D-158), changed only
/// by steppers: 1 to `maxSets` sets, reps 1 to `SetLogger.maxReps`, and the high end never
/// below the low end. Equal ends are one fixed number ("10").
public struct SlotShape: Sendable, Equatable {
  public static let maxSets = 10
  /// Add exercise's default, 3 x 8-12 (D-157).
  public static let added = SlotShape(sets: 3, repsLow: 8, repsHigh: 12)

  public private(set) var sets: Int
  public private(set) var repsLow: Int
  public private(set) var repsHigh: Int

  /// Clamped into range; a high end below the low end becomes the low end.
  public init(sets: Int, repsLow: Int, repsHigh: Int) {
    self.sets = min(max(sets, 1), Self.maxSets)
    self.repsLow = min(max(repsLow, 1), SetLogger.maxReps)
    self.repsHigh = min(max(repsHigh, self.repsLow), SetLogger.maxReps)
  }

  /// A slot's own sets and reps.
  public init(_ exercise: TemplateExercise) {
    self.init(sets: exercise.sets, repsLow: exercise.repsLow, repsHigh: exercise.repsHigh)
  }

  /// "3 x 8-12", or "3 x 10" for a fixed number.
  public var summary: String { "\(sets) x \(repRange)" }
  public var repRange: String { repsLow == repsHigh ? "\(repsLow)" : "\(repsLow)-\(repsHigh)" }

  public mutating func stepSets(up: Bool) {
    self = SlotShape(sets: sets + (up ? 1 : -1), repsLow: repsLow, repsHigh: repsHigh)
  }

  /// Raising the low end past the high end pushes the high end along.
  public mutating func stepRepsLow(up: Bool) {
    let low = min(max(repsLow + (up ? 1 : -1), 1), SetLogger.maxReps)
    self = SlotShape(sets: sets, repsLow: low, repsHigh: max(repsHigh, low))
  }

  /// Lowering the high end past the low end pulls the low end along.
  public mutating func stepRepsHigh(up: Bool) {
    let high = min(max(repsHigh + (up ? 1 : -1), 1), SetLogger.maxReps)
    self = SlotShape(sets: sets, repsLow: min(repsLow, high), repsHigh: high)
  }

  /// This shape on a slot: its sets and reps, the rest as it was.
  func applied(to exercise: TemplateExercise) -> TemplateExercise {
    var shaped = exercise
    (shaped.sets, shaped.repsLow, shaped.repsHigh) = (sets, repsLow, repsHigh)
    return shaped
  }
}
