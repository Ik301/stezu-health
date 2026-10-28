import StezuCore
import SwiftUI

/// This week's Health rows (S-022, S-039) from the same 8-week history as the detail (D-112). No
/// data shows "--" beside the coverage, never 0; with `hint`, a metric without data adds the
/// Sources hint. Blood oxygen and temperature have no row (D-093); Health still reads them.
struct WeeklyHealthRows: View {
  let metrics: [Metric]
  var reload = 0
  var hint = false
  var open: (Metric) -> Void = { _ in }
  @Environment(\.appEnvironment) private var environment
  @State private var histories: [Metric: MetricHistory] = [:]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(metrics) { metric in
        let week = histories[metric]?.weeks.first
        MetricRow(
          title: metric.title, id: metric.rawValue,
          coverage: week.map { coverage(metric, $0.stat.coverage) } ?? "--",
          values: histories[metric].map(ChartSeries.sparkline) ?? [],
          bars: metric == .steps || metric == .sleep, color: metric.color,
          value: week?.stat.value.map(metric.format) ?? "--", first: metric == metrics.first
        ) { open(metric) }
      }
      if hint, histories.count == metrics.count,
        histories.values.contains(where: { $0.weeks.first?.stat.value == nil })
      {
        label(HealthSources.deniedHint).accessibilityIdentifier("data.health.hint")
      }
    }
    .task(id: reload) {
      for metric in metrics {
        histories[metric] = await MetricHistory.load(
          metric, from: environment.weightHealth, now: environment.now())
      }
    }
  }

  private func coverage(_ metric: Metric, _ count: Int) -> String {
    if metric == .weight { return "Weigh-ins \(count) of 7" }
    if metric == .hrv { return "\(count) samples" }
    return "\(count) of 7 \(metric == .sleep || metric == .breathing ? "nights" : "days")"
  }

  private func label(_ text: String) -> some View {
    Text(text).textStyle(.label).foregroundStyle(Theme.muted)
  }
}
