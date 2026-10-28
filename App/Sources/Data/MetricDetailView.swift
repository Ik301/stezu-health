import StezuCore
import SwiftUI

/// One detail for every metric (S-024): the last 8 weeks, newest first, each with its value and
/// coverage, then the sources and how the value is made. Weight adds WeightChart. A tap on a
/// week lists its days, Monday to Sunday; a day without data shows "--". A day's chevron opens
/// everything recorded on it (S-025). S-042 draws the weeks above the list as WeekBars (food as
/// two panels, energy and protein); a bar opens its week as its row does. S-042b puts
/// CoverageDots before each week and adds Workouts (working sets).
struct MetricDetailView: View {
  let metric: Metric
  @Environment(\.appEnvironment) private var environment
  @Environment(\.dismiss) private var dismiss
  @State private var history: MetricHistory?
  @State private var meals: [LoggedMeal] = []
  @State private var openWeek: Int?
  @State private var openDay: Date?
  private let shape = RoundedRectangle(cornerRadius: Theme.radiusCard)

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.spaceMd) {
        TopBar(
          title: openDay?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            ?? metric.title, titleID: "metric.title", action: rung)
        if let openDay {
          DayView(day: openDay).padding(Theme.spaceLg).background(Theme.surface, in: shape)
        } else if let history, let index = openWeek {
          days(history.weeks[index]).padding(Theme.spaceLg).background(Theme.surface, in: shape)
        } else if let history {
          ForEach(panels(history), id: \.id) { panel in
            panel.padding(Theme.spaceLg).background(Theme.surface, in: shape)
          }
          if metric == .weight {
            WeightChart(history: history).padding(Theme.spaceLg).background(
              Theme.surface, in: shape)
          }
          weeks(history).padding(Theme.spaceLg).background(Theme.surface, in: shape)
        }
      }
      .textStyle(.body).foregroundStyle(Theme.ink).padding(Theme.spaceLg)
    }
    .scrollIndicators(.hidden)
    .background(Theme.ground.ignoresSafeArea())
    .task {
      let now = environment.now()
      switch metric {
      case .food:
        meals = await environment.mealCaptures.logged() + environment.mealHistory
        history = MetricHistory.food(meals, now: now)
      case .workouts:
        let finished = FinishedWorkoutStore(storage: environment.storage).load().map(\.session)
        history = MetricHistory.workouts(environment.workoutHistory + finished, now: now)
      default:
        history = await MetricHistory.load(metric, from: environment.weightHealth, now: now)
      }
    }
  }

  /// One WeekBars well per plot: food's energy and protein are two, never one.
  private func panels(_ history: MetricHistory) -> [WeekBars] {
    let (now, ofSeven) = (environment.now(), metric != .hrv && metric != .workouts)
    let describe: (Int) -> String = { summary(history.weeks[$0]).label }
    let open: (Int) -> Void = { openWeek = $0 }
    guard metric == .food else {
      return [
        WeekBars(
          title: metric.title, bars: ChartSeries.weekBars(history), color: metric.color,
          id: "metric.weekbars", ofSeven: ofSeven, describe: describe, open: open)
      ]
    }
    return [
      WeekBars(
        title: "Energy, kcal per logged day", bars: ChartSeries.rangeBands(meals, \.kcal, now: now),
        color: Theme.dataEnergy, band: Theme.dataEnergyBand, id: "metric.energy",
        describe: describe, open: open),
      WeekBars(
        title: "Protein, g per logged day",
        bars: ChartSeries.rangeBands(meals, \.protein, now: now),
        color: Theme.dataProtein, band: Theme.dataProteinBand, id: "metric.protein",
        describe: describe, open: open),
    ]
  }

  /// A week's dates, coverage and value, and the words VoiceOver reads for its row and its bar.
  private func summary(_ week: MetricWeek) -> (
    dates: String, covered: String, value: String, label: String
  ) {
    let dates = range(week.start)
    let unit = metric == .sleep || metric == .breathing ? "nights" : "days"
    let count = week.stat.coverage
    let covered =
      metric == .hrv
      ? "\(count) samples"
      : metric == .workouts ? "\(count) session\(count == 1 ? "" : "s")" : "\(count) of 7 \(unit)"
    let value = text(week.stat.value, from: week.start, days: 7)
    return (dates, covered, value, "\(dates), \(covered), \(value)")
  }

  /// Food shows its energy and protein ranges ("1,000–1,320 kcal, 52–68 g"); the rest a value.
  private func text(_ value: Double?, from start: Date, days: Double) -> String {
    guard metric == .food else { return value.map(metric.format) ?? "--" }
    let food = WeeklyIntake.food(meals, in: DateInterval(start: start, duration: days * 86_400))
    guard let kcal = food.kcal.value, let protein = food.protein.value else { return "--" }
    let ranged = { (range: FoodRange) in
      "\(Int(range.low.rounded()).formatted())–\(Int(range.high.rounded()).formatted())"
    }
    return "\(ranged(kcal)) kcal, \(ranged(protein)) g"
  }

  /// Done on the 8 weeks; the rung above on a week or a day.
  private var rung: TopBar.Action {
    if openDay != nil { return .init(title: "Week", id: "metric.day.back") { openDay = nil } }
    if openWeek != nil { return .init(title: "8 weeks", id: "metric.back") { openWeek = nil } }
    return .init(title: "Done", id: "metric.close") { dismiss() }
  }

  private func weeks(_ history: MetricHistory) -> some View {
    VStack(alignment: .leading, spacing: Theme.spaceMd) {
      ForEach(Array(history.weeks.enumerated()), id: \.offset) { index, week in
        let (dates, covered, value, words) = summary(week)
        // The dots sit outside the row's button, which would swallow them as an element.
        HStack(spacing: Theme.spaceSm) {
          if metric != .hrv {
            CoverageDots(
              days: ChartSeries.coverage(week, of: metric, now: environment.now()),
              id: "metric.week.\(index).dots"
            )
            .frame(width: 54, alignment: .leading)
          }
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
          .accessibilityLabel(words)
          .accessibilityIdentifier("metric.week.\(index)")
        }
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
          Text(text(day.value, from: day.day, days: 1)).textStyle(.value)
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
    case .food: "Food"
    case .breathing: "Breathing"
    case .workouts: "Workouts"
    }
  }

  func format(_ value: Double) -> String {
    switch self {
    case .weight: String(format: "%.1f lb", value)
    case .steps: "\(Int(value.rounded()))"
    case .sleep: "\(Int(value / 3600))h \(Int(value / 60) % 60)m"
    case .hrv: "\(Int(value.rounded())) ms"
    case .restingHR: "\(Int(value.rounded())) bpm"
    case .food: "\(Int(value.rounded())) kcal"
    case .breathing: String(format: "%.1f br/min", value)
    case .workouts: "\(Int(value.rounded())) set\(Int(value.rounded()) == 1 ? "" : "s")"
    }
  }

  /// data-heart for resting HR, data-energy for food, ink for the rest (S-042).
  var color: Color {
    self == .restingHR ? Theme.dataHeart : self == .food ? Theme.dataEnergy : Theme.ink
  }
}
