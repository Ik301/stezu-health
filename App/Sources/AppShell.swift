import SwiftUI

/// The three areas behind the Home cards. The raw value is the card id and the stem of the
/// accessibility ids ("home.card.food", "screen.food.title").
enum Area: String, CaseIterable, Sendable {
  case data, food, workout
}

/// Home, or one area at a time. S-001 adds the bottom nav of three circles.
struct AppShell: View {
  @State private var area: Area?

  var body: some View {
    switch area {
    case nil:
      HomeView(open: { area = $0 })
    case .data?:
      DataView(goHome: { area = nil })
    case .food?:
      FoodView(goHome: { area = nil })
    case .workout?:
      WorkoutView(goHome: { area = nil })
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
