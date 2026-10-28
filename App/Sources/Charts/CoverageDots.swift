import SwiftUI

/// A week's days from Monday up to today (design/system/components/CoverageDots): filled in ink
/// where there is data, a track ring where there is none; days to come are not drawn. Hidden
/// from VoiceOver, because the words beside the dots say the same. Under -uitest it is one
/// element (`id`, "n of m") so a UI test can find it. Days come from `ChartSeries.coverage`.
struct CoverageDots: View {
  let days: [Bool]
  var id = "coverage.dots"
  @Environment(\.appEnvironment) private var environment

  var body: some View {
    HStack(spacing: Theme.space2xs) {
      ForEach(Array(days.enumerated()), id: \.offset) { _, filled in
        if filled {
          Circle().fill(Theme.ink).frame(width: 6, height: 6)
        } else {
          Circle().strokeBorder(Theme.track, lineWidth: 1).frame(width: 6, height: 6)
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(days.filter { $0 }.count) of \(days.count)")
    .accessibilityIdentifier(id)
    .accessibilityHidden(!environment.isUITest)
  }
}
