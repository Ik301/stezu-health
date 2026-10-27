import SwiftUI

/// The three areas behind the Home cards. The raw value is the card id and the stem of the
/// accessibility ids ("home.card.food", "screen.food.title").
enum Area: String, CaseIterable, Sendable {
  case data, food, workout
}

/// Home, or one area at a time. Every area screen gets the bottom nav of three circles, which
/// switches areas in one tap; the shell owns the current area, so area views never navigate.
struct AppShell: View {
  /// Settings saved a server; the app rebuilds its VM transport from it.
  var serverSaved: (ServerSettings) -> Void = { _ in }
  @State private var area: Area?
  @State private var settingsOpen = false
  @Environment(\.appEnvironment) private var environment

  var body: some View {
    if let area {
      areaView(area)
        .safeAreaInset(edge: .bottom, spacing: 0) {
          BottomNav(active: area, open: { self.area = $0 })
        }
    } else {
      HomeView(open: { area = $0 }, openSettings: { settingsOpen = true })
        .sheet(isPresented: $settingsOpen) {
          SettingsView(saved: serverSaved)
            .presentationDragIndicator(.visible)
            .environment(\.appEnvironment, environment)
        }
    }
  }

  @ViewBuilder
  private func areaView(_ area: Area) -> some View {
    switch area {
    case .data:
      DataView(goHome: { self.area = nil })
    case .food:
      FoodView(goHome: { self.area = nil })
    case .workout:
      WorkoutView(goHome: { self.area = nil })
    }
  }
}

/// The frame every area screen shares: the TopBar (Home, an optional text action, the title
/// that UI tests find as "screen.<area>.title"), then the area's content.
struct AreaScaffold<Content: View>: View {
  let area: Area
  let title: String
  var action: TopBar.Action? = nil
  let goHome: () -> Void
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spaceMd) {
      TopBar(title: title, titleID: "screen.\(area.rawValue).title", home: goHome, action: action)
      content
      Spacer(minLength: 0)
    }
    .padding(Theme.spaceLg)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Theme.ground.ignoresSafeArea())
  }
}

/// The top of every area screen and sheet (design/system/components/TopBar): Home on the left of
/// an area screen ("nav.home"), one text action on the right, and beneath them the title in
/// title-1, saying what the screen holds now. Sheets have no Home and never use toolbar items,
/// which iOS 26 draws as floating glass pills; their action is Done or the rung above.
struct TopBar: View {
  let title: String
  let titleID: String
  var home: (() -> Void)? = nil
  var action: Action? = nil

  /// The right slot: one text button, such as "Finish", "Sources", "Done" or "8 weeks".
  struct Action {
    let title: String
    let id: String
    let run: () -> Void
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spaceXs) {
      HStack(spacing: Theme.spaceSm) {
        if let home {
          Button(action: home) {
            Image(systemName: "house").textStyle(.value)
              .frame(width: Theme.sizeTarget, height: Theme.sizeTarget).contentShape(Rectangle())
          }
          .accessibilityLabel("Home").accessibilityIdentifier("nav.home")
        }
        Spacer(minLength: 0)
        if let action {
          Button(action: action.run) {
            Text(action.title).textStyle(.headline).padding(.leading, Theme.spaceSm)
              .frame(minHeight: Theme.sizeTarget).contentShape(Rectangle())
          }
          .accessibilityIdentifier(action.id)
        }
      }
      .buttonStyle(.plain)
      .frame(minHeight: Theme.sizeTarget)
      Text(title).textStyle(.title1)
        .accessibilityAddTraits(.isHeader).accessibilityIdentifier(titleID)
    }
    .foregroundStyle(Theme.ink)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
