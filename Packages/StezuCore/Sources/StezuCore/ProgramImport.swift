import Foundation

/// A program file picked in the Files app. It uses the bundled seed's format; its seedVersion is
/// read but not compared, since an import always applies.
public enum ProgramImport {
  /// Why a file was refused, in words the import screen shows.
  public enum Failure: Error, Equatable, Sendable {
    case unreadable(String)
    case noTemplates
    case invalid(String)

    public var message: String {
      switch self {
      case .unreadable(let detail): return "Not a program file: \(detail)"
      case .noTemplates: return "The file has no templates."
      case .invalid(let detail): return detail
      }
    }
  }

  /// Decodes and checks the whole file; any problem refuses all of it.
  public static func parse(_ data: Data) -> Result<[WorkoutTemplate], Failure> {
    let seed: WorkoutSeed
    do {
      seed = try WorkoutSeed.decode(data)
    } catch let DecodingError.keyNotFound(key, _) {
      return .failure(.unreadable("missing \"\(key.stringValue)\""))
    } catch let DecodingError.typeMismatch(_, context) {
      return .failure(.unreadable("wrong type at \(path(context.codingPath))"))
    } catch let DecodingError.valueNotFound(_, context) {
      return .failure(.unreadable("no value at \(path(context.codingPath))"))
    } catch {
      return .failure(.unreadable("invalid JSON"))
    }
    guard !seed.templates.isEmpty else { return .failure(.noTemplates) }
    var keys = Set<String>()
    for template in seed.templates {
      if let problem = check(template, seen: keys) { return .failure(.invalid(problem)) }
      keys.insert(template.key)
    }
    return .success(seed.templates)
  }

  private static func check(_ template: WorkoutTemplate, seen: Set<String>) -> String? {
    let label = template.name.isEmpty ? template.key : template.name
    if template.key.isEmpty { return "A template has no key." }
    if seen.contains(template.key) { return "Template key \"\(template.key)\" appears twice." }
    if template.name.isEmpty { return "Template \"\(template.key)\" has no name." }
    for exercise in template.exercises {
      let name = exercise.name.isEmpty ? exercise.key : exercise.name
      if exercise.key.isEmpty || exercise.name.isEmpty {
        return "An exercise in \(label) has no key or name."
      }
      if exercise.sets < 1 { return "\(name) in \(label) needs at least 1 set." }
      if exercise.repsLow < 1 || exercise.repsHigh < exercise.repsLow {
        return "\(name) in \(label) has an invalid rep range."
      }
      if exercise.restSeconds < 0 { return "\(name) in \(label) has negative rest." }
    }
    return nil
  }

  private static func path(_ codingPath: [any CodingKey]) -> String {
    codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
  }
}

extension TemplateLibrary {
  /// Applies a program file: each template replaces the one with its key (or is appended) and is
  /// kept from later seeds like an edit. An invalid file changes nothing. Returns the count.
  public mutating func importProgram(_ data: Data) -> Result<Int, ProgramImport.Failure> {
    ProgramImport.parse(data).map { templates in
      for template in templates { edit(template) }
      return templates.count
    }
  }
}
