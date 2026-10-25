import Foundation

/// A countdown between sets. It stores only the start time and reads the time from an injected
/// clock, so it is correct after the app is suspended and tests never sleep.
public struct RestTimer {
  public enum State: Equatable, Sendable {
    /// Not started, or stopped.
    case idle
    case resting(remaining: TimeInterval)
    /// The rest is over; `overBy` is how long ago it ended.
    case done(overBy: TimeInterval)
  }

  /// Rest length in seconds. A default, not a personal number.
  public let duration: TimeInterval
  public private(set) var startedAt: Date?
  private let now: () -> Date

  /// `duration` must be positive and finite. `now` is the clock; pass `{ Date() }` in the app.
  public init(duration: TimeInterval = 90, now: @escaping () -> Date) {
    precondition(duration.isFinite && duration > 0, "rest duration must be positive")
    self.duration = duration
    self.now = now
  }

  /// Starts (or restarts) the rest from the clock's current time, as when a set is logged.
  public mutating func start() {
    startedAt = now()
  }

  public mutating func stop() {
    startedAt = nil
  }

  /// Seconds left, or nil when the timer is idle. Never negative.
  public var remaining: TimeInterval? {
    guard let startedAt else { return nil }
    return max(0, duration - now().timeIntervalSince(startedAt))
  }

  public var state: State {
    guard let startedAt else { return .idle }
    let elapsed = now().timeIntervalSince(startedAt)
    return elapsed < duration
      ? .resting(remaining: duration - elapsed) : .done(overBy: elapsed - duration)
  }
}
