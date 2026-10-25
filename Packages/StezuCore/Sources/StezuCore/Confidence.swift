/// How far a derived value can be trusted, and why.
public struct Confidence: Sendable, Equatable {
  public enum Level: Int, Sendable, Comparable {
    case low
    case medium
    case high

    public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  public let level: Level
  /// A short, human-readable reason, such as the number of weigh-ins behind a trend.
  public let reason: String

  public init(level: Level, reason: String) {
    self.level = level
    self.reason = reason
  }
}
