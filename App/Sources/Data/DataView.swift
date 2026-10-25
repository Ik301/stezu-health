import SwiftUI

/// The Data area's root screen. A placeholder until the Data stories build it; keep the
/// "screen.data.title" id on its title so the smoke UI test still finds it.
struct DataView: View {
  var goHome: () -> Void = {}

  var body: some View {
    AreaScaffold(area: .data, title: "This week", goHome: goHome) {
      Text("Nothing here yet.")
        .font(.system(size: Theme.subtitleSize))
        .foregroundStyle(Theme.label)
    }
  }
}

#Preview {
  DataView()
}
