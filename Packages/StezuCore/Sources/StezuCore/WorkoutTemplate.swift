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
  /// An optional block (S-035, D-084), appended to a running workout instead of done as a day.
  public var addOn: Bool

  public init(key: String, name: String, exercises: [TemplateExercise], addOn: Bool = false) {
    (self.key, self.name, self.exercises, self.addOn) = (key, name, exercises, addOn)
  }

  private enum CodingKeys: String, CodingKey { case key, name, exercises, addOn }

  /// Files and libraries without the flag (before S-035) decode as days.
  public init(from decoder: any Decoder) throws {
    let box = try decoder.container(keyedBy: CodingKeys.self)
    key = try box.decode(String.self, forKey: .key)
    name = try box.decode(String.self, forKey: .name)
    exercises = try box.decode([TemplateExercise].self, forKey: .exercises)
    addOn = try box.decodeIfPresent(Bool.self, forKey: .addOn) ?? false
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
  /// True once a program file replaced the templates; the bundled seed is skipped from then on.
  public private(set) var programImported = false
  /// Names of templates an import removed, by key, so their past sessions keep their names.
  public private(set) var removedNames: [String: String] = [:]

  public init() {}

  private enum CodingKeys: String, CodingKey {
    case seedVersion, templates, editedKeys, programImported, removedNames
  }

  /// Library files saved before S-034 have no import flag or removed names.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    seedVersion = try container.decodeIfPresent(Int.self, forKey: .seedVersion)
    templates = try container.decode([WorkoutTemplate].self, forKey: .templates)
    editedKeys = try container.decode(Set<String>.self, forKey: .editedKeys)
    programImported =
      try container.decodeIfPresent(Bool.self, forKey: .programImported) ?? false
    removedNames =
      try container.decodeIfPresent([String: String].self, forKey: .removedNames) ?? [:]
  }

  /// Template names by key for history: the current templates, then removed ones.
  public var names: [String: String] {
    removedNames.merging(
      Dictionary(templates.map { ($0.key, $0.name) }, uniquingKeysWith: { a, _ in a }),
      uniquingKeysWith: { _, current in current })
  }

  /// Applies a seed newer than the last: each template replaces the one with its key (or is
  /// appended) unless the user edited it; others stay. False if the seed is not newer, or once
  /// a program was imported, so a seed never brings removed templates back.
  @discardableResult
  public mutating func upsert(_ seed: WorkoutSeed) -> Bool {
    if programImported { return false }
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

  /// Makes the templates exactly these, in this order (D-083). Removed templates keep their
  /// names for history; sessions are stored elsewhere and are never touched.
  public mutating func replaceProgram(with program: [WorkoutTemplate]) {
    let kept = Set(program.map(\.key))
    for old in templates where !kept.contains(old.key) { removedNames[old.key] = old.name }
    templates = program
    editedKeys.formUnion(kept)
    programImported = true
  }

  private mutating func put(_ template: WorkoutTemplate) {
    if let index = templates.firstIndex(where: { $0.key == template.key }) {
      templates[index] = template
    } else {
      templates.append(template)
    }
  }

  /// The templates done as days, in rotation order; add-ons are left out.
  public var days: [WorkoutTemplate] { templates.filter { !$0.addOn } }

  /// The add-on blocks a running workout can append (S-035).
  public var addOns: [WorkoutTemplate] { templates.filter(\.addOn) }

  /// The day after the last one done, wrapping around; the first when none was done or the
  /// last one no longer exists. Nil only when there are no days. Add-ons are never next.
  public func next(after lastKey: String?) -> WorkoutTemplate? {
    let days = days
    guard let lastKey, let index = days.firstIndex(where: { $0.key == lastKey }) else {
      return days.first
    }
    return days[(index + 1) % days.count]
  }
}
