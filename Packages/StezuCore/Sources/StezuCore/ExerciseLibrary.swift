import Foundation

/// One exercise in the Exercises library. A custom exercise's key starts with "custom-".
public struct LibraryExercise: Sendable, Equatable, Codable {
  public var key: String
  public var name: String
  public var equipment: String  // such as "Barbell"; empty when not given
  public var muscle: String
  public var restSeconds: Int

  public var isCustom: Bool { key.hasPrefix("custom-") }
}

/// The exercises Isaac can swap in: the bundled generic list plus his custom ones.
public struct ExerciseLibrary: Sendable, Equatable, Codable {
  public private(set) var exercises: [LibraryExercise]

  public init(exercises: [LibraryExercise] = []) { self.exercises = exercises }

  public var custom: [LibraryExercise] { exercises.filter(\.isCustom) }

  /// Exercises whose name contains `query`, ignoring case (all for an empty query), by name.
  public func search(_ query: String) -> [LibraryExercise] {
    let text = query.trimmingCharacters(in: .whitespaces)
    let found = exercises.filter {
      text.isEmpty || $0.name.range(of: text, options: .caseInsensitive) != nil
    }
    return found.sorted { ($0.name.lowercased(), $0.key) < ($1.name.lowercased(), $1.key) }
  }

  /// The search result grouped by muscle, muscles in alphabetical order.
  public func groupedByMuscle(_ query: String) -> [(muscle: String, exercises: [LibraryExercise])] {
    Dictionary(grouping: search(query), by: \.muscle).sorted { $0.key < $1.key }
      .map { (muscle: $0.key, exercises: $0.value) }
  }

  /// Adds a custom exercise keyed "custom-<name slug>", with "-2", "-3" when that key is taken;
  /// the key never changes afterwards. Nil for an empty name or a rest below 1 second.
  @discardableResult
  public mutating func addCustom(
    name: String, equipment: String, muscle: String, restSeconds: Int
  ) -> LibraryExercise? {
    let name = name.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty, restSeconds > 0 else { return nil }
    let words = name.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
    let base = "custom-" + (words.isEmpty ? "exercise" : words.joined(separator: "-"))
    var (key, number) = (base, 2)
    while exercises.contains(where: { $0.key == key }) {
      (key, number) = ("\(base)-\(number)", number + 1)
    }
    let muscle = muscle.trimmingCharacters(in: .whitespaces)
    let exercise = LibraryExercise(
      key: key, name: name, equipment: equipment.trimmingCharacters(in: .whitespaces),
      muscle: muscle.isEmpty ? "Other" : muscle, restSeconds: restSeconds)
    exercises.append(exercise)
    return exercise
  }

  /// When the exercise was last done before `date`: "today", "7d ago", or "--" if never.
  public static func lastDone(_ name: String, before date: Date, in sessions: [WorkoutSession])
    -> String
  {
    let days = WorkoutHistory.lastSession(of: name, before: date, in: sessions)?.daysAgo
    return days.map { $0 == 0 ? "today" : "\($0)d ago" } ?? "--"
  }
}

extension TemplateExercise {
  /// This slot's sets and rep range with the library exercise's name, key and rest.
  public func replaced(by exercise: LibraryExercise) -> TemplateExercise {
    TemplateExercise(
      key: exercise.key, name: exercise.name, sets: sets, repsLow: repsLow, repsHigh: repsHigh,
      restSeconds: exercise.restSeconds)
  }
}
