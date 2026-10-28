import Accessibility
import SwiftUI

/// A chart's Audio Graph: one series over named categories (weeks or days), so VoiceOver can play
/// it. A point without data has no value, never 0.
struct ChartAudio: AXChartDescriptorRepresentable {
  let title: String
  let points: [(label: String, value: Double?)]

  func makeChartDescriptor() -> AXChartDescriptor {
    let values = points.compactMap { $0.value }
    let low = values.min() ?? 0
    return AXChartDescriptor(
      title: title, summary: nil,
      xAxis: AXCategoricalDataAxisDescriptor(title: "Date", categoryOrder: points.map { $0.label }),
      yAxis: AXNumericDataAxisDescriptor(
        title: title, range: low...max(values.max() ?? 1, low), gridlinePositions: []
      ) { "\(Int($0.rounded()))" },
      additionalAxes: [],
      series: [
        AXDataSeriesDescriptor(
          name: title, isContinuous: false,
          dataPoints: points.map { AXDataPoint(x: $0.label, y: $0.value) })
      ])
  }
}
