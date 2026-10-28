import Charts
import StezuCore
import SwiftUI

/// Weigh-in dots and the trend line over the 8 weeks (design/system/components/WeightChart):
/// weigh-ins in data-sample, the trend in data-trend, and its last point a dot with a surface
/// ring. Three gridlines at whole pounds, labelled on the left; week starts are the x ticks. A
/// day without a weigh-in draws nothing.
struct WeightChart: View {
  let history: MetricHistory

  var body: some View {
    let points = history.trend
    let values = points.flatMap { [$0.pounds, $0.trend] }
    let (low, high) = ((values.min() ?? 0) - 0.6, (values.max() ?? 1) + 0.6)
    let grid =
      points.isEmpty ? [] : Set([ceil(low), ((low + high) / 2).rounded(), floor(high)]).sorted()
    let weeks = history.weeks.reversed().map(\.start)
    let start = weeks.first ?? Date()
    Chart {
      ForEach(points, id: \.day) { point in
        PointMark(x: .value("Day", point.day), y: .value("Weigh-in", point.pounds))
          .foregroundStyle(Theme.dataSample).symbolSize(20)
        LineMark(x: .value("Day", point.day), y: .value("Trend", point.trend))
          .foregroundStyle(Theme.dataTrend)
          .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
      }
      if let last = points.last {
        PointMark(x: .value("Day", last.day), y: .value("Trend", last.trend))
          .foregroundStyle(Theme.surface).symbolSize(113)
        PointMark(x: .value("Day", last.day), y: .value("Trend", last.trend))
          .foregroundStyle(Theme.dataTrend).symbolSize(50)
      }
    }
    .chartXScale(domain: start...start.addingTimeInterval(56 * 86_400))
    .chartYScale(domain: low...high)
    .chartXAxis {
      AxisMarks(values: weeks) { _ in
        AxisTick().foregroundStyle(Theme.track)
        AxisValueLabel(format: .dateTime.month(.defaultDigits).day()).foregroundStyle(Theme.muted)
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading, values: grid) { value in
        AxisGridLine().foregroundStyle(Theme.track)
        AxisValueLabel { Text("\(Int(value.as(Double.self) ?? 0))").textStyle(.axis) }
          .foregroundStyle(Theme.muted)
      }
    }
    .chartLegend(.hidden)
    .frame(height: Theme.sizeChart)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(points.isEmpty ? "No weigh-ins" : "\(points.count) weigh-ins and the trend")
    .accessibilityIdentifier("metric.chart")
    .accessibilityChartDescriptor(
      ChartAudio(
        title: "Weight trend",
        points: points.map { (label: $0.day.formatted(.dateTime.month().day()), value: $0.trend) }))
  }
}
