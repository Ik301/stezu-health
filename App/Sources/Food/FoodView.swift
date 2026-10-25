import SwiftUI

/// The Food area's root screen. A placeholder until the Food stories build it; keep the
/// "screen.food.title" id on its title so the smoke UI test still finds it.
struct FoodView: View {
  var goHome: () -> Void = {}

  var body: some View {
    AreaScaffold(area: .food, title: "Food", goHome: goHome) {
      Text("Nothing here yet.")
        .font(.system(size: Theme.subtitleSize))
        .foregroundStyle(Theme.label)
    }
  }
}

#Preview {
  FoodView()
}
