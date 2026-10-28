import Charts
import SwiftUI

/// A week's days, Monday to Sunday, in 72 x 28 (design/system/components/MetricRow): a line for
/// levels, bars for counts. A day without data is a dashed track slot, never 0, and breaks the
/// line; a 0 (a rest day in Workouts) is a baseline stub. Today is at full strength, with a dot
/// on a line; earlier days are at 55%. Values come from `ChartSeries.sparkline`.
struct Sparkline: View {
  let title: String
  let values: [Double?]
  var bars = false
  var color = Theme.ink
  /// Today's index, Monday 0; 6 for a past week.
  var today = 6

  var body: some View {
    let known = values.compactMap { $0 }
    let (low, high) = (known.min() ?? 0, known.max() ?? 1)
    let pad = max(high - low, 1) * 0.15
    let (base, top) = bars ? (0, max(high, 1)) : (low - pad, high + pad)
    let names = Calendar.current.shortWeekdaySymbols  // Sunday first
    Chart {
      ForEach(Array(values.enumerated()), id: \.offset) { day, value in
        let x = Double(day)
        let strength: Double = day == today ? 1 : 0.55
        if let value, bars, value > 0 {
          BarMark(
            x: .value("Day", x), yStart: .value(title, 0), yEnd: .value(title, value),
            width: .fixed(6)
          )
          .foregroundStyle(color).opacity(strength).cornerRadius(1.5)
        } else if let value, !bars {
          // A new series after each gap, so the line breaks there.
          LineMark(
            x: .value("Day", x), y: .value(title, value),
            series: .value("Run", values[..<day].filter { $0 == nil }.count)
          )
          .foregroundStyle(color).opacity(0.55)
          .lineStyle(StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
          let lone =
            (day == 0 || values[day - 1] == nil)
            && (day == values.count - 1 || values[day + 1] == nil)
          if day == today || lone {
            PointMark(x: .value("Day", x), y: .value(title, value))
              .foregroundStyle(color).opacity(strength).symbolSize(day == today ? 20 : 10)
          }
        } else {
          RuleMark(
            xStart: .value("Day", x - 0.3), xEnd: .value("Day", x + 0.3), y: .value(title, base)
          )
          .foregroundStyle(value == nil ? Theme.track : color).opacity(value == nil ? 1 : strength)
          .lineStyle(
            value == nil ? StrokeStyle(lineWidth: 1, dash: [2, 2]) : StrokeStyle(lineWidth: 2))
        }
      }
    }
    .chartXScale(domain: -0.5...Double(values.count) - 0.5)
    .chartYScale(domain: base...top)
    .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
    .frame(width: 72, height: Theme.sizeSpark)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityChartDescriptor(
      ChartAudio(
        title: title,
        points: values.indices.map { (label: names[($0 + 1) % 7], value: values[$0]) }))
  }
}
