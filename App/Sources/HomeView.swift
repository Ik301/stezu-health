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
  var inputs = HomeInputs()

  var body: some View {
    // Re-read the clock every minute so the inverted card follows the time of day.
    TimelineView(.everyMinute) { _ in
      let inverted = model.invertedCardID()
      VStack(spacing: 12) {
        ForEach(model.cards(inputs)) { card in
          HomeCardView(card: card, inverted: card.id == inverted)
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Theme.background.ignoresSafeArea())
    }
  }
}

struct HomeCardView: View {
  let card: HomeCard
  let inverted: Bool
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(card.label)
        .font(.system(size: Theme.labelSize))
        .foregroundStyle(Theme.label)
      Text(card.subtitle)
        .font(.system(size: Theme.subtitleSize))
        .foregroundStyle(inverted ? Theme.invertedText : Theme.text)
      Spacer(minLength: 0)
      Text(card.value)
        .font(.system(size: Theme.bigNumberSize, weight: .medium))
        .tracking(Theme.bigNumberTracking)
        .foregroundStyle(inverted ? Theme.invertedText : Theme.text)
    }
    .padding(18)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        .fill(inverted ? Theme.invertedCard : Theme.card)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        .strokeBorder(Theme.cardBorder, lineWidth: inverted ? 0 : 1 / displayScale)
    )
    .accessibilityElement(children: .combine)
  }
}

#Preview {
  HomeView()
}
