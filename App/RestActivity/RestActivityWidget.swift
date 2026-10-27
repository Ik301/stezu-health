import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RestActivityBundle: WidgetBundle {
  var body: some Widget {
    RestActivityWidget()
  }
}

/// The rest countdown on the lock screen and in the Dynamic Island. Minimal on purpose: the
/// Workout stories decide when it starts, changes and ends.
struct RestActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RestActivityAttributes.self) { context in
      RestLockScreenView(exerciseName: context.attributes.exerciseName, state: context.state)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.attributes.exerciseName)
            .font(.headline)
        }
        DynamicIslandExpandedRegion(.trailing) {
          RestCountdown(state: context.state)
            .font(.title2.monospacedDigit())
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(context.state.setLabel)
            .foregroundStyle(.secondary)
        }
      } compactLeading: {
        Image(systemName: "timer")
      } compactTrailing: {
        RestCountdown(state: context.state)
          .monospacedDigit()
          .frame(maxWidth: 48)
      } minimal: {
        Image(systemName: "timer")
      }
    }
  }
}

/// Counts down to the end of the rest; the system redraws it without app updates.
struct RestCountdown: View {
  let state: RestActivityAttributes.ContentState

  var body: some View {
    Text(timerInterval: state.startedAt...max(state.startedAt, state.endsAt), countsDown: true)
  }
}

struct RestLockScreenView: View {
  let exerciseName: String
  let state: RestActivityAttributes.ContentState

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: Theme.space2xs) {
        Text("Rest")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(exerciseName)
          .font(.headline)
        Text(state.setLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      RestCountdown(state: state)
        .textStyle(.big, weight: .semibold)
        .multilineTextAlignment(.trailing)
    }
    .padding(Theme.spaceLg)
  }
}
