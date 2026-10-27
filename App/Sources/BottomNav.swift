import SwiftUI

/// The bottom nav on every area screen (DESIGN.md): three 58 pt circles, Data, Food and Workout.
/// The active area's circle is black. Each circle is "nav.circle.<area>", and its accessibility
/// value is "active" or "inactive" so UI tests can read which one is black.
struct BottomNav: View {
  let active: Area
  let open: (Area) -> Void

  var body: some View {
    HStack(spacing: Theme.spaceXl) {
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
    .padding(.vertical, Theme.spaceMd)
    .background(Theme.ground.ignoresSafeArea())
  }
}

struct NavCircle: View {
  let title: String
  let isActive: Bool
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    Text(title)
      .textStyle(.label, weight: .medium)
      .foregroundStyle(isActive ? Theme.onInvert : Theme.ink)
      .frame(width: Theme.sizeNav, height: Theme.sizeNav)
      .background(Circle().fill(isActive ? Theme.invert : Theme.surface))
      .overlay(Circle().strokeBorder(Theme.edge, lineWidth: isActive ? 0 : 1 / displayScale))
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
