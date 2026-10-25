import Foundation
import StezuCore

/// One rest as the lock screen and the zero notification see it.
struct RestAlert: Sendable, Equatable {
  var exerciseName: String
  /// The set just logged, for example "Set 1 of 3".
  var setLabel: String
  var startedAt: Date
  var endsAt: Date
}

/// What the phone shows outside the app during a rest: the RestActivity Live Activity and a
/// local notification at zero. `LiveRestAlerts` on the phone, `FakeRestAlerts` in `-uitest`.
protocol RestAlerts: Sendable {
  /// Starts the Live Activity (ending any older one) and schedules the zero notification.
  func start(_ alert: RestAlert)
  /// Moves the Live Activity and the notification to the alert's new end.
  func update(_ alert: RestAlert)
  /// Ends the Live Activity and cancels the notification.
  func end()
}

/// Records the calls instead of showing anything.
final class FakeRestAlerts: RestAlerts, @unchecked Sendable {
  enum Call: Equatable {
    case start(RestAlert)
    case update(RestAlert)
    case end
  }

  private let lock = NSLock()
  private var recorded: [Call] = []

  var calls: [Call] { lock.withLock { recorded } }
  func start(_ alert: RestAlert) { lock.withLock { recorded.append(.start(alert)) } }
  func update(_ alert: RestAlert) { lock.withLock { recorded.append(.update(alert)) } }
  func end() { lock.withLock { recorded.append(.end) } }
}

/// The rest on the logger: a RestTimer that starts by itself when a set is logged, at that
/// exercise's template rest, with the Live Activity and the zero notification kept in step.
struct RestActivityController {
  let alerts: any RestAlerts
  private let now: () -> Date
  private(set) var timer: RestTimer?
  private var alert: RestAlert?

  init(alerts: any RestAlerts, now: @escaping () -> Date = { Date() }) {
    self.alerts = alerts
    self.now = now
  }

  var remaining: TimeInterval? { timer?.remaining }
  var startedAt: Date? { timer?.startedAt }
  var endsAt: Date? { timer?.endsAt }

  /// Starts (or restarts) the rest for the set just logged. A template rest of 0 starts none.
  mutating func setLogged(_ exercise: TemplateExercise, setLabel: String) {
    guard exercise.restSeconds > 0 else {
      skip()
      return
    }
    var timer = RestTimer(duration: TimeInterval(exercise.restSeconds), now: now)
    timer.start()
    guard let startedAt = timer.startedAt, let endsAt = timer.endsAt else { return }
    let alert = RestAlert(
      exerciseName: exercise.name, setLabel: setLabel, startedAt: startedAt, endsAt: endsAt)
    (self.timer, self.alert) = (timer, alert)
    alerts.start(alert)
  }

  /// +15 s or -15 s: the end moves, the start stays. Shortening to zero ends the rest.
  mutating func adjust(by seconds: TimeInterval) {
    guard var timer, var alert else { return }
    timer.adjust(by: seconds)
    self.timer = timer
    guard case .resting = timer.state, let endsAt = timer.endsAt else {
      skip()
      return
    }
    alert.endsAt = endsAt
    self.alert = alert
    alerts.update(alert)
  }

  /// Ends the rest now; the countdown goes away.
  mutating func skip() {
    guard timer != nil else { return }
    (timer, alert) = (nil, nil)
    alerts.end()
  }

  /// Ends the rest once the countdown has reached zero.
  mutating func tick() {
    if case .done = timer?.state { skip() }
  }

  /// "2:30"; "--" when no rest runs.
  static func text(_ remaining: TimeInterval?) -> String {
    guard let remaining else { return "--" }
    let seconds = Int(remaining.rounded(.up))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
}
