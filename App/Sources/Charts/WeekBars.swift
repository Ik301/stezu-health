import Charts
import StezuCore
import SwiftUI

/// Eight weekly bars, oldest on the left (design/system/components/WeekBars): a solid bar in the
/// metric's colour, or for an estimate (food) a low-to-high band with a 3 pt midpoint; a week
/// without data is a dashed slot with "--" above it, never 0. The current week is at full
/// strength, past weeks at 55%. Two gridlines, no y-axis numbers: the list below has the values.
/// Each week's column is a button (`<id>.bar.<week>`, week 0 the current one) that opens it.
struct WeekBars: View {
  let title: String
  let bars: [WeekBar]
  var color = Theme.ink
  var band = Theme.ink
  let id: String
  /// Coverage under a bar reads "n/7", or "n" for sample counts (HRV).
  var ofSeven = true
  /// The VoiceOver words for a week, by its index in the list (0 is the current week).
  var describe: (Int) -> String = { _ in "" }
  var open: (Int) -> Void = { _ in }

  var body: some View {
    let top = max(bars.compactMap { $0.band?.high ?? $0.value }.max() ?? 1, 1)
    let keys = bars.map { $0.start.formatted(.dateTime.month(.defaultDigits).day()) }
    VStack(alignment: .leading, spacing: Theme.spaceSm) {
      Text(title).textStyle(.label).foregroundStyle(Theme.muted)
      ZStack(alignment: .top) {
        Chart {
          RuleMark(y: .value("Grid", top)).foregroundStyle(Theme.track)
          RuleMark(y: .value("Grid", top / 2)).foregroundStyle(Theme.track)
          ForEach(Array(bars.enumerated()), id: \.offset) { index, bar in
            let strength = index == bars.count - 1 ? 1.0 : 0.55
            if let range = bar.band, let mid = bar.value {
              RectangleMark(
                x: .value("Week", keys[index]), yStart: .value("Low", range.low),
                yEnd: .value("High", range.high), width: .ratio(0.6)
              )
              .foregroundStyle(band).opacity(strength)
              RectangleMark(
                x: .value("Week", keys[index]), y: .value("Midpoint", mid), width: .ratio(0.6),
                height: .fixed(3)
              )
              .foregroundStyle(color).opacity(strength)
            } else if let value = bar.value {
              BarMark(x: .value("Week", keys[index]), y: .value(title, value), width: .ratio(0.6))
                .foregroundStyle(color).opacity(strength).cornerRadius(3)
            }
          }
        }
        .chartXScale(domain: keys).chartYScale(domain: 0...top * 1.05)
        .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
        .frame(height: Theme.sizeChart)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), 8 weeks")
        .accessibilityIdentifier(id)
        .accessibilityChartDescriptor(
          ChartAudio(
            title: title, points: bars.indices.map { (label: keys[$0], value: bars[$0].value) }))
        HStack(spacing: 0) {
          ForEach(Array(bars.enumerated()), id: \.offset) { index, bar in
            column(bar, key: keys[index], week: bars.count - 1 - index)
          }
        }
      }
    }
  }

  /// A week's tap target over its bar, with its date and coverage beneath; an absent week also
  /// draws its dashed slot and "--" here.
  private func column(_ bar: WeekBar, key: String, week: Int) -> some View {
    Button {
      open(week)
    } label: {
      VStack(spacing: Theme.space2xs) {
        VStack(spacing: Theme.space2xs) {
          Spacer(minLength: 0)
          if bar.value == nil {
            Text("--")
            RoundedRectangle(cornerRadius: Theme.spaceXs)
              .strokeBorder(Theme.track, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
              .frame(height: Theme.sizeSpark).padding(.horizontal, Theme.spaceSm)
          }
        }
        .frame(height: Theme.sizeChart)
        Text(key)
        Text(ofSeven ? "\(bar.coverage)/7" : "\(bar.coverage)")
      }
      .textStyle(.axis).foregroundStyle(Theme.muted)
      .frame(maxWidth: .infinity).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(describe(week))
    .accessibilityIdentifier("\(id).bar.\(week)")
  }
}
