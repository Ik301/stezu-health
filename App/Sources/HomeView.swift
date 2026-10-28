import StezuCore
import SwiftUI

/// The cards before any data exists: every value is missing.
enum HomePlaceholder {
  static let missing = HomeViewModel.missing
  static let coreVersion = StezuCore.version
  static let cards: [HomeCard] = HomeViewModel().cards(HomeInputs())
}

/// Home: three GlanceCards sharing the height evenly, never scrolling (S-037).
struct HomeView: View {
  var model = HomeViewModel()
  /// Opens the area behind a tapped card.
  var open: (Area) -> Void = { _ in }
  /// Opens Settings from the gear.
  var openSettings: () -> Void = {}
  @Environment(\.appEnvironment) private var environment
  /// Read each time Home appears, so a card shows what an area just recorded.
  @State private var inputs = HomeInputs()

  /// The model on the launch's clock, so a scenario's week and the dots agree.
  private var clocked: HomeViewModel {
    var copy = self.model
    copy.now = environment.now
    return copy
  }

  var body: some View {
    // Re-read the clock every minute so the inverted card follows the time of day.
    TimelineView(.everyMinute) { _ in
      let model = clocked
      let inverted = model.invertedCardID(workoutInProgress: inputs.workoutInProgress)
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
          // The card is one element, so a UI test reads Workout's dots from its value (S-048).
          .accessibilityValue(
            environment.isUITest ? card.dots.map { CoverageDots.marks($0) } ?? "" : ""
          )
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

/// One GlanceCard (design/system/components/GlanceCard): the area and its time frame, the
/// number centred in the space between with its picture on the right, and the detail row.
struct HomeCardView: View {
  let card: HomeCard
  let inverted: Bool
  @Environment(\.displayScale) private var displayScale
  @Environment(\.colorScheme) private var scheme

  private var ink: Color { inverted ? Theme.onInvert : Theme.ink }
  private var muted: Color { inverted ? Theme.onInvertMuted : Theme.muted }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        Text(card.label).textStyle(.subtitle, weight: .medium).foregroundStyle(ink)
        Spacer(minLength: Theme.spaceSm)
        Text(card.frame).textStyle(.label).foregroundStyle(muted)
      }
      Spacer(minLength: Theme.spaceXs)
      HStack(spacing: Theme.spaceMd) {
        HStack(alignment: .firstTextBaseline, spacing: Theme.space2xs) {
          ForEach(Array(card.amounts.enumerated()), id: \.offset) { _, amount in
            Text(amount.number).textStyle(.big).lineLimit(1).minimumScaleFactor(0.4)
            if !amount.unit.isEmpty {
              Text(amount.unit).textStyle(.subtitle).lineLimit(1)
                .padding(.trailing, Theme.spaceXs)
            }
          }
        }
        .foregroundStyle(ink)
        .layoutPriority(1)
        Spacer(minLength: 0)
        picture
          // The picture's ink and track flip with the card, so they stay legible on invert.
          .environment(\.colorScheme, inverted ? (scheme == .dark ? .light : .dark) : scheme)
      }
      Spacer(minLength: Theme.spaceXs)
      HStack(alignment: .firstTextBaseline) {
        fact(card.left)
        Spacer(minLength: Theme.spaceSm)
        fact(card.right)
      }
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
    .accessibilityLabel(card.accessibilityLabel)
  }

  @ViewBuilder
  private var picture: some View {
    if let bars = card.bars {
      Sparkline(title: "Nights this week", values: bars, bars: true, today: card.today)
    } else if let dots = card.dots {
      CoverageDots(days: dots, id: "home.\(card.id).dots", size: 12)
    }
  }

  /// A detail fact: muted words with the value in ink.
  private func fact(_ fact: HomeCard.Fact) -> some View {
    Text("\(fact.before)\(Text(fact.value).foregroundStyle(ink))\(fact.after)")
      .textStyle(.label).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.8)
  }
}

#Preview {
  HomeView()
}
