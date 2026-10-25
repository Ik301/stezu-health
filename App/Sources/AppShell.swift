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

/// The frame every area screen shares for now: a Home button at the top left ("nav.home") and a
/// title that UI tests find as "screen.<area>.title".
struct AreaScaffold<Content: View>: View {
  let area: Area
  let title: String
  let goHome: () -> Void
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button {
        goHome()
      } label: {
        Image(systemName: "house")
          .font(.system(size: 17, weight: .medium))
          .foregroundStyle(Theme.text)
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel("Home")
      .accessibilityIdentifier("nav.home")
      Text(title)
        .font(.system(size: 34, weight: .semibold))
        .foregroundStyle(Theme.text)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("screen.\(area.rawValue).title")
      content
      Spacer(minLength: 0)
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Theme.background.ignoresSafeArea())
  }
}
