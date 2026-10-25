import Foundation

/// The logger behind the black Log card: the set being prepared (its weight and reps, changed
/// only by steppers) and the session it logs into. Logging moves to the next set; undo takes
/// back the last set and puts its numbers back on the card. Codable, so the app can save it
/// after every change.
public struct SetLogger: Sendable, Equatable, Codable {
  public static let defaultWeightStep: Double = 5
  public static let maxPounds: Double = 2000
  public static let maxReps = 100

  public let template: WorkoutTemplate
  public private(set) var session: WorkoutSession
  /// The template exercise the card is on.
  public private(set) var exerciseIndex = 0
  /// The prepared weight; nil before one is set ("--"). Ignored while `isBodyweight`.
  public private(set) var pounds: Double?
  public private(set) var reps: Int
  /// A bodyweight set: logged with `pounds == nil`, never 0.
  public private(set) var isBodyweight = false
  /// The exercise index of every logged set, oldest first, so undo knows the last one.
  private var logOrder: [Int] = []

  public init(template: WorkoutTemplate, startedAt: Date) {
    self.template = template
    session = WorkoutSession(startedAt: startedAt)
    let first = template.exercises.first
    pounds = first?.startPounds
    reps = first?.repsLow ?? 1
  }

  public var exercise: TemplateExercise? {
    template.exercises.indices.contains(exerciseIndex) ? template.exercises[exerciseIndex] : nil
  }

  public var weightStep: Double { exercise?.weightStep ?? Self.defaultWeightStep }

  /// 1-based number of the set on the card.
  public var setNumber: Int { (exercise.flatMap { session.sets(for: $0.name)?.count } ?? 0) + 1 }

  /// Sets logged for the exercise on the card, oldest first.
  public var loggedSets: [WorkoutSet] { exercise.flatMap { session.sets(for: $0.name) } ?? [] }

  /// True while there is a logged set to take back.
  public var canUndo: Bool { !logOrder.isEmpty }

  /// Log needs an exercise and either a weight or bodyweight.
  public var canLog: Bool { exercise != nil && (isBodyweight || pounds != nil) }

  /// Logs the card's numbers in one call. After the exercise's last set the card moves to the
  /// next exercise with that exercise's starting numbers; otherwise the numbers stay.
  @discardableResult
  public mutating func log(at date: Date) -> WorkoutSet? {
    guard canLog, let exercise,
      let set = session.logSet(
        exercise.name, pounds: isBodyweight ? nil : pounds, reps: reps, at: date)
    else { return nil }
    logOrder.append(exerciseIndex)
    let done = session.sets(for: exercise.name)?.count ?? 0
    if done >= exercise.sets, exerciseIndex + 1 < template.exercises.count {
      exerciseIndex += 1
      let next = template.exercises[exerciseIndex]
      (pounds, reps, isBodyweight) = (next.startPounds, next.repsLow, false)
    }
    return set
  }

  /// Removes only the last logged set and returns the card to it with its numbers.
  @discardableResult
  public mutating func undo() -> WorkoutSet? {
    guard let index = logOrder.last,
      let set = session.removeLastSet(of: template.exercises[index].name)
    else { return nil }
    logOrder.removeLast()
    exerciseIndex = index
    (isBodyweight, reps) = (set.pounds == nil, set.reps)
    if let weight = set.pounds { pounds = weight }
    return set
  }

  /// One weight step up or down, kept within one step and `maxPounds`. Starts at one step when
  /// no weight is set. Does nothing for a bodyweight set.
  public mutating func stepWeight(up: Bool) {
    guard !isBodyweight else { return }
    let step = weightStep
    guard let current = pounds else {
      if up { pounds = step }
      return
    }
    pounds = min(max(current + (up ? step : -step), step), Self.maxPounds)
  }

  /// One rep up or down, kept within 1 and `maxReps`.
  public mutating func stepReps(up: Bool) {
    reps = min(max(reps + (up ? 1 : -1), 1), Self.maxReps)
  }

  /// Switches between a bodyweight set and the prepared weight, which is kept for switching back.
  public mutating func toggleBodyweight() {
    isBodyweight.toggle()
  }
}
