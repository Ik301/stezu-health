import StezuCore
import SwiftUI

/// One detail for every metric (S-024): the last 8 weeks, newest first, each with its value and
/// coverage, then the sources and how the value is made. Weight adds weigh-in dots and the trend
/// line. A tap on a week lists its days, Monday to Sunday; a day without data shows "--". A
/// day's chevron opens everything recorded on it (S-025).
struct MetricDetailView: View {
  let metric: Metric
  @Environment(\.appEnvironment) private var environment
  @Environment(\.dismiss) private var dismiss
  @State private var history: MetricHistory?
  @State private var openWeek: Int?
  @State private var openDay: Date?
  private let shape = RoundedRectangle(cornerRadius: Theme.radiusCard)

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.spaceMd) {
        if openDay != nil {
          Button("Week") { openDay = nil }.accessibilityIdentifier("metric.day.back")
        } else if openWeek == nil {
          Button("Done") { dismiss() }.accessibilityIdentifier("metric.close")
        } else {
          Button("8 weeks") { openWeek = nil }.accessibilityIdentifier("metric.back")
        }
        Text(openDay?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) ?? metric.title)
          .textStyle(.title1).accessibilityIdentifier("metric.title")
        if let openDay {
          DayView(day: openDay).padding(Theme.spaceLg).background(Theme.surface, in: shape)
        } else if let history, let index = openWeek {
          days(history.weeks[index]).padding(Theme.spaceLg).background(Theme.surface, in: shape)
        } else if let history {
          if metric == .weight {
            TrendChart(history: history).padding(Theme.spaceLg).background(Theme.surface, in: shape)
          }
          weeks(history).padding(Theme.spaceLg).background(Theme.surface, in: shape)
        }
      }
      .textStyle(.body).foregroundStyle(Theme.ink).padding(Theme.spaceLg)
    }
    .scrollIndicators(.hidden)
    .background(Theme.ground.ignoresSafeArea())
    .task {
      history = await MetricHistory.load(
        metric, from: environment.weightHealth, now: environment.now())
    }
  }

  private func weeks(_ history: MetricHistory) -> some View {
    VStack(alignment: .leading, spacing: Theme.spaceMd) {
      ForEach(Array(history.weeks.enumerated()), id: \.offset) { index, week in
        let dates = range(week.start)
        let unit = metric == .sleep ? "nights" : "days"
        let covered =
          metric == .hrv ? "\(week.stat.coverage) samples" : "\(week.stat.coverage) of 7 \(unit)"
        let value = week.stat.value.map(metric.format) ?? "--"
        Button {
          openWeek = index
        } label: {
          HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Theme.space2xs) {
              Text(dates).textStyle(.headline)
              label(covered)
            }
            Spacer()
            Text(value).textStyle(.value)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(dates), \(covered), \(value)")
        .accessibilityIdentifier("metric.week.\(index)")
      }
      let sources = history.sources.joined(separator: ", ")
      label("From: " + (sources.isEmpty ? "--" : sources)).accessibilityIdentifier("metric.sources")
      label(metric.note).accessibilityIdentifier("metric.note")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func days(_ week: MetricWeek) -> some View {
    VStack(alignment: .leading, spacing: Theme.spaceMd) {
      label(range(week.start))
      ForEach(Array(week.days.enumerated()), id: \.offset) { index, day in
        HStack {
          Text(day.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
            .accessibilityIdentifier("metric.day.\(index).name")
          Spacer()
          Text(day.value.map(metric.format) ?? "--").textStyle(.value)
            .accessibilityIdentifier("metric.day.\(index).value")
          Button {
            openDay = day.day
          } label: {
            Image(systemName: "chevron.right").textStyle(.subtitle, weight: .semibold)
              .foregroundStyle(Theme.muted).frame(width: Theme.sizeTarget, height: 22)
              .contentShape(Rectangle())
          }
          .accessibilityLabel("Everything on this day")
          .accessibilityIdentifier("metric.day.\(index).open")
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func range(_ start: Date) -> String {
    let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
    let style = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
    return "\(start.formatted(style)) to \(end.formatted(style))"
  }

  private func label(_ text: String) -> some View {
    Text(text).textStyle(.label).foregroundStyle(Theme.muted)
  }
}

/// Weigh-in dots and the trend line across the 8 weeks, oldest on the left.
private struct TrendChart: View {
  let history: MetricHistory

  var body: some View {
    let points = history.trend
    let start = history.weeks.last?.start ?? Date()
    let span = max((history.weeks.first?.start ?? start).timeIntervalSince(start) + 7 * 86_400, 1)
    Canvas { context, size in
      let values = points.flatMap { [$0.pounds, $0.trend] }
      guard let low = values.min(), let high = values.max() else { return }
      let pad = max((high - low) * 0.1, 0.5)
      func at(_ point: TrendPoint, _ pounds: Double) -> CGPoint {
        CGPoint(
          x: size.width * point.day.timeIntervalSince(start) / span,
          y: size.height * (1 - (pounds - low + pad) / (high - low + 2 * pad)))
      }
      var line = Path()
      line.addLines(points.map { at($0, $0.trend) })
      context.stroke(line, with: .color(Theme.ink), lineWidth: 2)
      for point in points {
        let dot = CGRect(origin: at(point, point.pounds), size: .zero).insetBy(dx: -3, dy: -3)
        context.fill(Path(ellipseIn: dot), with: .color(Theme.muted))
      }
    }
    .frame(height: 120)
    .accessibilityElement()
    .accessibilityAddTraits(.isImage)
    .accessibilityLabel(points.isEmpty ? "No weigh-ins" : "\(points.count) weigh-ins and the trend")
    .accessibilityIdentifier("metric.chart")
  }
}

/// An overview row's way into its metric's weeks.
struct MetricOpenButton: View {
  let metric: Metric
  let open: (Metric) -> Void

  var body: some View {
    Button {
      open(metric)
    } label: {
      Image(systemName: "chevron.right").textStyle(.subtitle, weight: .semibold)
        .foregroundStyle(Theme.muted).frame(width: Theme.sizeTarget, height: 22)
        .contentShape(Rectangle())
    }
    .accessibilityLabel("\(metric.title) weeks")
    .accessibilityIdentifier("data.\(metric.rawValue).open")
  }
}

extension Metric {
  var title: String {
    switch self {
    case .weight: "Weight"
    case .steps: "Steps"
    case .sleep: "Sleep"
    case .hrv: "HRV"
    case .restingHR: "Resting HR"
    }
  }

  func format(_ value: Double) -> String {
    switch self {
    case .weight: String(format: "%.1f lb", value)
    case .steps: "\(Int(value.rounded()))"
    case .sleep: "\(Int(value / 3600))h \(Int(value / 60) % 60)m"
    case .hrv: "\(Int(value.rounded())) ms"
    case .restingHR: "\(Int(value.rounded())) bpm"
    }
  }
}
