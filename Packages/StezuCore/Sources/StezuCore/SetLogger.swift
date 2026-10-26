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
  /// The slot and exercise name of every logged set, oldest first, so undo knows the last one.
  private var logOrder: [LoggedSlot] = []
  /// Each exercise's last-session numbers, same template first (TemplateHistory); exercises never
  /// done before have no key.
  public private(set) var last: [String: LastSessionNumbers]
  /// Exercises swapped in from the library for this session only, by template slot. The
  /// template itself never changes.
  public private(set) var swaps: [Int: TemplateExercise] = [:]

  private struct LoggedSlot: Sendable, Equatable, Codable {
    let index: Int
    let name: String
  }

  /// Prefills each exercise from its last session's first set, else from the template's start.
  public init(
    template: WorkoutTemplate, startedAt: Date, history: [WorkoutSession] = [],
    config: WorkoutHistoryConfig = WorkoutHistoryConfig()
  ) {
    self.template = template
    session = WorkoutSession(startedAt: startedAt, templateKey: template.key)
    last = TemplateHistory.lastSessions(
      for: template, before: startedAt, in: history, config: config)
    reps = 1
    if let first = template.exercises.first { prefill(first) }
  }

  /// The last-session numbers of the exercise on the card; nil the first time it is done.
  public var lastNumbers: LastSessionNumbers? { exercise.flatMap { last[$0.name] } }

  private mutating func prefill(_ exercise: TemplateExercise) {
    if let set = last[exercise.name]?.sets.first {
      (pounds, reps, isBodyweight) = (
        set.pounds ?? exercise.startPounds, set.reps, set.pounds == nil
      )
    } else {
      (pounds, reps, isBodyweight) = (exercise.startPounds, exercise.repsLow, false)
    }
  }

  public var exercise: TemplateExercise? {
    template.exercises.indices.contains(exerciseIndex) ? exerciseInSlot(exerciseIndex) : nil
  }

  private func exerciseInSlot(_ index: Int) -> TemplateExercise {
    swaps[index] ?? template.exercises[index]
  }

  /// Puts a library exercise in the card's slot for this session only, keeping the slot's sets
  /// and reps, and prefills it from its last session of any template, else with no weight.
  public mutating func swap(to replacement: LibraryExercise, history: [WorkoutSession]) {
    guard let current = exercise else { return }
    let swapped = current.replaced(by: replacement)
    swaps[exerciseIndex] = swapped
    last[swapped.name] = WorkoutHistory.lastSession(
      of: swapped.name, before: session.startedAt, in: history)
    prefill(swapped)
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
    logOrder.append(LoggedSlot(index: exerciseIndex, name: exercise.name))
    let done = session.sets(for: exercise.name)?.count ?? 0
    if done >= exercise.sets, exerciseIndex + 1 < template.exercises.count {
      exerciseIndex += 1
      prefill(exerciseInSlot(exerciseIndex))
    }
    return set
  }

  /// Removes only the last logged set and returns the card to it with its numbers.
  @discardableResult
  public mutating func undo() -> WorkoutSet? {
    guard let slot = logOrder.last, let set = session.removeLastSet(of: slot.name)
    else { return nil }
    logOrder.removeLast()
    exerciseIndex = slot.index
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
