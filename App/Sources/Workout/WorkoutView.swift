import SwiftUI

/// The Workout area's root screen. A placeholder until the Workout stories build it; keep the
/// "screen.workout.title" id on its title so the smoke UI test still finds it.
struct WorkoutView: View {
  var goHome: () -> Void = {}

  var body: some View {
    AreaScaffold(area: .workout, title: "Workout", goHome: goHome) {
      Text("Nothing here yet.")
        .font(.system(size: Theme.subtitleSize))
        .foregroundStyle(Theme.label)
    }
  }
}

#Preview {
  WorkoutView()
}
