import StezuCore
import SwiftUI

/// One home card. The value is display text, and missing data is "--", never 0.
struct HomeCard: Identifiable, Equatable, Sendable {
  let id: String
  let label: String
  let subtitle: String
  let value: String
  /// Confidence of the derived value; nil when the value is missing or not derived.
  var confidence: Confidence? = nil
}

/// The cards before any data exists: every value is missing.
enum HomePlaceholder {
  static let missing = HomeViewModel.missing
  static let coreVersion = StezuCore.version
  static let cards: [HomeCard] = HomeViewModel().cards(HomeInputs())
}

struct HomeView: View {
  var model = HomeViewModel()
  /// Opens the area behind a tapped card.
  var open: (Area) -> Void = { _ in }
  /// Opens Settings from the gear.
  var openSettings: () -> Void = {}
  @Environment(\.appEnvironment) private var environment
  /// Read each time Home appears, so a card shows what an area just recorded.
  @State private var inputs = HomeInputs()

  var body: some View {
    // Re-read the clock every minute so the inverted card follows the time of day.
    TimelineView(.everyMinute) { _ in
      let inverted = model.invertedCardID()
      VStack(spacing: Theme.spaceMd) {
        HStack {
          Spacer()
          Button(action: openSettings) {
            Image(systemName: "gearshape")
              .textStyle(.value)
              .foregroundStyle(Theme.ink)
              .frame(width: Theme.sizeTarget, height: Theme.sizeTarget)
          }
          .accessibilityLabel("Settings")
          .accessibilityIdentifier("home.settings")
        }
        ForEach(model.cards(inputs)) { card in
          Button {
            if let area = Area(rawValue: card.id) { open(area) }
          } label: {
            HomeCardView(card: card, inverted: card.id == inverted)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("home.card.\(card.id)")
        }
      }
      .padding(Theme.spaceLg)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Theme.ground.ignoresSafeArea())
    }
    .task { inputs = await HomeInputs.load(from: environment) }
  }
}

struct HomeCardView: View {
  let card: HomeCard
  let inverted: Bool
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spaceXs) {
      Text(card.label)
        .textStyle(.label)
        .foregroundStyle(inverted ? Theme.onInvertMuted : Theme.muted)
      Text(card.subtitle)
        .textStyle(.subtitle)
        .foregroundStyle(inverted ? Theme.onInvert : Theme.ink)
      Spacer(minLength: 0)
      Text(card.value)
        .textStyle(.big)
        .foregroundStyle(inverted ? Theme.onInvert : Theme.ink)
    }
    .padding(Theme.spaceCard)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
        .fill(inverted ? Theme.invert : Theme.surface)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
        .strokeBorder(Theme.edge, lineWidth: inverted ? 0 : 1 / displayScale)
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(card.label), \(card.subtitle), \(card.value)")
  }
}

#Preview {
  HomeView()
}
