import SwiftUI

/// A week's 7 days, Monday to Sunday (design/system/components/CoverageDots, GlanceCard): filled
/// in ink where there is data, a track ring where there is none, today outlined in ink and days
/// to come faint (S-048). `days` runs from Monday up to today in the current week, or all 7 in
/// a past week. Hidden from VoiceOver, because the words beside the dots say the same. Under
/// -uitest it is one element (`id`, "n of m", its `marks` as the value, such as "1001t--").
/// Days come from `ChartSeries.coverage`.
struct CoverageDots: View {
  let days: [Bool]
  var id = "coverage.dots"
  /// The week holds today: its last day is today and the rest of the 7 are still to come.
  var current = true
  var size: CGFloat = 6
  @Environment(\.appEnvironment) private var environment

  /// The 7 days as marks: 1 filled, 0 a ring, t or T today unfilled or filled, - to come.
  static func marks(_ days: [Bool], current: Bool = true) -> String {
    String(
      (0..<7).map { day -> Character in
        guard day < days.count else { return "-" }
        if current && day == days.count - 1 { return days[day] ? "T" : "t" }
        return days[day] ? "1" : "0"
      })
  }

  var body: some View {
    let marks = Self.marks(days, current: current)
    HStack(spacing: size / 2) {
      ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
        Circle().fill("1T".contains(mark) ? Theme.ink : .clear)
          .overlay(
            Circle().strokeBorder(
              "1Tt".contains(mark) ? Theme.ink : Theme.track, lineWidth: max(1, size / 8))
          )
          .opacity(mark == "-" ? 0.4 : 1)
          .frame(width: size, height: size)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(days.filter { $0 }.count) of \(days.count)")
    .accessibilityValue(marks)
    .accessibilityIdentifier(id)
    .accessibilityHidden(!environment.isUITest)
  }
}
