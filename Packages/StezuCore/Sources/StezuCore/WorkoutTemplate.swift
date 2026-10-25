import Foundation

/// One exercise in a template: how many sets, the rep range and the rest between sets.
public struct TemplateExercise: Sendable, Equatable, Codable {
  public var key: String
  public var name: String
  public var sets: Int
  public var repsLow: Int
  public var repsHigh: Int
  public var restSeconds: Int
  /// Pounds per weight stepper tap; nil means the default (SetLogger.defaultWeightStep).
  public var weightStep: Double?
  /// The weight prefilled before any history, such as an empty bar; nil shows "--".
  public var startPounds: Double?

  public init(
    key: String, name: String, sets: Int, repsLow: Int, repsHigh: Int, restSeconds: Int,
    weightStep: Double? = nil, startPounds: Double? = nil
  ) {
    (self.key, self.name, self.sets) = (key, name, sets)
    (self.repsLow, self.repsHigh, self.restSeconds) = (repsLow, repsHigh, restSeconds)
    (self.weightStep, self.startPounds) = (weightStep, startPounds)
  }

  /// "8-12", or "8" when the range is one number.
  public var repRange: String { repsLow == repsHigh ? "\(repsLow)" : "\(repsLow)-\(repsHigh)" }
}

/// A named workout, identified by a stable key so a newer seed or an import can replace it.
public struct WorkoutTemplate: Sendable, Equatable, Codable {
  public var key: String
  public var name: String
  public var exercises: [TemplateExercise]

  public init(key: String, name: String, exercises: [TemplateExercise]) {
    (self.key, self.name, self.exercises) = (key, name, exercises)
  }
}

/// The bundled PrebuiltWorkouts.json: a generic program (D-034) and the version that orders seeds.
public struct WorkoutSeed: Sendable, Equatable, Codable {
  public var seedVersion: Int
  public var templates: [WorkoutTemplate]

  public init(seedVersion: Int, templates: [WorkoutTemplate]) {
    (self.seedVersion, self.templates) = (seedVersion, templates)
  }

  public static func decode(_ data: Data) throws -> WorkoutSeed {
    try JSONDecoder().decode(WorkoutSeed.self, from: data)
  }
}

/// The templates on the device, in rotation order. Workout history is stored elsewhere, so
/// nothing here can change it.
public struct TemplateLibrary: Sendable, Equatable, Codable {
  /// The last seed applied; nil before the first one.
  public private(set) var seedVersion: Int?
  public private(set) var templates: [WorkoutTemplate] = []
  /// Keys of templates the user changed; a seed never overwrites them.
  public private(set) var editedKeys: Set<String> = []

  public init() {}

  /// Applies a seed newer than the last: each template replaces the one with its key (or is
  /// appended) unless the user edited it; others stay. False if the seed is not newer.
  @discardableResult
  public mutating func upsert(_ seed: WorkoutSeed) -> Bool {
    if let seedVersion, seed.seedVersion <= seedVersion { return false }
    for template in seed.templates where !editedKeys.contains(template.key) {
      put(template)
    }
    seedVersion = seed.seedVersion
    return true
  }

  /// Saves the user's change to a template and protects it from later seeds.
  public mutating func edit(_ template: WorkoutTemplate) {
    put(template)
    editedKeys.insert(template.key)
  }

  private mutating func put(_ template: WorkoutTemplate) {
    if let index = templates.firstIndex(where: { $0.key == template.key }) {
      templates[index] = template
    } else {
      templates.append(template)
    }
  }

  /// The template after the last one done, wrapping around; the first when none was done or the
  /// last one no longer exists. Nil only when there are no templates.
  public func next(after lastKey: String?) -> WorkoutTemplate? {
    guard let lastKey, let index = templates.firstIndex(where: { $0.key == lastKey }) else {
      return templates.first
    }
    return templates[(index + 1) % templates.count]
  }
}
