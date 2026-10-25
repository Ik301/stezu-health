import ActivityKit
import Foundation
import UserNotifications

/// The phone's rest alerts: the RestActivity Live Activity (App/Shared) and one pending local
/// notification for zero. It keeps no state; it finds its activities through
/// `Activity.activities` and its notification by identifier.
struct LiveRestAlerts: RestAlerts {
  static let notificationID = "rest.end"

  func start(_ alert: RestAlert) {
    Task {
      await Self.endActivities()
      if ActivityAuthorizationInfo().areActivitiesEnabled {
        _ = try? Activity<RestActivityAttributes>.request(
          attributes: RestActivityAttributes(exerciseName: alert.exerciseName),
          content: Self.content(alert), pushType: nil)
      }
      await Self.schedule(alert)
    }
  }

  func update(_ alert: RestAlert) {
    Task {
      for activity in Activity<RestActivityAttributes>.activities {
        await activity.update(Self.content(alert))
      }
      await Self.schedule(alert)
    }
  }

  func end() {
    Task {
      await Self.endActivities()
      UNUserNotificationCenter.current()
        .removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }
  }

  private static func content(_ alert: RestAlert) -> ActivityContent<
    RestActivityAttributes.ContentState
  > {
    let state = RestActivityAttributes.ContentState(
      startedAt: alert.startedAt, endsAt: alert.endsAt, setLabel: alert.setLabel)
    return ActivityContent(state: state, staleDate: alert.endsAt)
  }

  private static func endActivities() async {
    for activity in Activity<RestActivityAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  /// Replaces the pending zero notification with one at `alert.endsAt`.
  private static func schedule(_ alert: RestAlert) async {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [notificationID])
    let allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    let seconds = alert.endsAt.timeIntervalSinceNow
    guard allowed, seconds >= 1 else { return }
    let content = UNMutableNotificationContent()
    content.title = "Rest over"
    content.body = "\(alert.exerciseName), after \(alert.setLabel.lowercased())"
    content.sound = .default
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
    try? await center.add(
      UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger))
  }
}
