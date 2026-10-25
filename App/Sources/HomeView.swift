import StezuCore
import SwiftUI

/// One home card. The value is display text, and missing data is "--", never 0.
struct HomeCard: Identifiable, Equatable, Sendable {
  let id: String
  let label: String
  let subtitle: String
  let value: String
}

/// Placeholder content until F-005 adds the view model.
enum HomePlaceholder {
  static let missing = "--"
  static let coreVersion = StezuCore.version
  static let cards: [HomeCard] = [
    HomeCard(id: "data", label: "Data", subtitle: "Trend weight, this week", value: missing),
    HomeCard(id: "food", label: "Food", subtitle: "Today against target", value: missing),
    HomeCard(id: "workout", label: "Workout", subtitle: "Last session", value: missing),
  ]
}

struct HomeView: View {
  var cards: [HomeCard] = HomePlaceholder.cards
  /// The inverted "log this now" card. F-005 picks it by time of day.
  var invertedCardID: String? = "food"

  var body: some View {
    VStack(spacing: 12) {
      ForEach(cards) { card in
        HomeCardView(card: card, inverted: card.id == invertedCardID)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.background.ignoresSafeArea())
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
