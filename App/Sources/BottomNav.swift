import SwiftUI

/// The bottom nav on every area screen (DESIGN.md): three 58 pt circles, Data, Food and Workout.
/// The active area's circle is black. Each circle is "nav.circle.<area>", and its accessibility
/// value is "active" or "inactive" so UI tests can read which one is black.
struct BottomNav: View {
  let active: Area
  let open: (Area) -> Void

  var body: some View {
    HStack(spacing: 24) {
      ForEach(Area.allCases, id: \.self) { area in
        Button {
          open(area)
        } label: {
          NavCircle(title: area.title, isActive: area == active)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(area.title)
        .accessibilityValue(area == active ? "active" : "inactive")
        .accessibilityAddTraits(area == active ? .isSelected : [])
        .accessibilityIdentifier("nav.circle.\(area.rawValue)")
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .background(Theme.background.ignoresSafeArea())
  }
}

struct NavCircle: View {
  let title: String
  let isActive: Bool
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    Text(title)
      .font(.system(size: Theme.labelSize, weight: .medium))
      .foregroundStyle(isActive ? Theme.invertedText : Theme.text)
      .frame(width: Theme.navCircleSize, height: Theme.navCircleSize)
      .background(Circle().fill(isActive ? Theme.invertedCard : Theme.card))
      .overlay(Circle().strokeBorder(Theme.cardBorder, lineWidth: isActive ? 0 : 1 / displayScale))
  }
}

extension Area {
  /// The name on the Home card and the nav circle.
  var title: String {
    switch self {
    case .data: "Data"
    case .food: "Food"
    case .workout: "Workout"
    }
  }
}

#Preview {
  BottomNav(active: .workout, open: { _ in })
}
