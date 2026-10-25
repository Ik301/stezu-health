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

  /// Rest length in seconds, including any +15/-15 adjustments. A default, not a personal number.
  public private(set) var duration: TimeInterval
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

  /// Lengthens (positive) or shortens (negative) a running rest, keeping its start time. The
  /// length never goes below 0, which ends the rest. Does nothing when idle.
  public mutating func adjust(by seconds: TimeInterval) {
    guard startedAt != nil, seconds.isFinite else { return }
    duration = max(0, duration + seconds)
  }

  /// Ends the rest now, as the Skip button does: the timer goes back to idle.
  public mutating func skip() {
    stop()
  }

  /// When the rest ends, or nil when idle.
  public var endsAt: Date? { startedAt?.addingTimeInterval(duration) }

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
