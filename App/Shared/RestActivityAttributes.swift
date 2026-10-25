import ActivityKit
import Foundation

/// The rest timer's Live Activity. The app starts, updates and ends it; the RestActivity widget
/// extension draws it on the lock screen and in the Dynamic Island. Both targets compile this file.
struct RestActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    /// When the rest started and when it ends; the system counts down between the two.
    var startedAt: Date
    var endsAt: Date
    /// For example "Set 2 of 4".
    var setLabel: String
  }

  /// The exercise being rested between, for example "Bench press".
  var exerciseName: String
}
