import StezuCore
import SwiftUI

/// The overview's Weight row for this Monday-to-Sunday week (S-021): trend, the trend's change
/// this week, weigh-in days out of 7, the confidence reason and the apps the trend uses. Weigh in
/// opens a stepper prefilled with the last weigh-in; Save writes one sample and reloads the row.
struct WeightRow: View {
  @Environment(\.appEnvironment) private var environment
  @State private var loaded: (week: WeekWeight, prefill: Double?)?
  @State private var pounds = 0.0
  @State private var weighing = false
  @State private var reloads = 0

  var body: some View {
    let week = loaded?.week
    let sources = week?.sources.joined(separator: ", ") ?? ""
    VStack(alignment: .leading, spacing: 6) {
      label(week.map { weekRange($0.weekStart) } ?? "--").accessibilityIdentifier("data.week.range")
      HStack(alignment: .firstTextBaseline) {
        Text("Weight").font(.system(size: 17, weight: .semibold))
        Spacer()
        Text(week?.trend.map { String(format: "%.1f lb", $0) } ?? "--")
          .font(.system(size: Theme.bigNumberSize, weight: .medium))
          .tracking(Theme.bigNumberTracking)
          .accessibilityIdentifier("data.weight.trend")
      }
      label("This week: " + (week?.change.map { String(format: "%+.1f lb", $0) } ?? "--"))
        .accessibilityIdentifier("data.weight.change")
      label("Weigh-ins: " + (week?.daysWeighed.map { "\($0) of 7" } ?? "--"))
        .accessibilityIdentifier("data.weight.coverage")
      label(week?.confidence.reason ?? "--").accessibilityIdentifier("data.weight.reason")
      label("From: " + (sources.isEmpty ? "--" : sources)).accessibilityIdentifier(
        "data.weight.sources")
      Button("Weigh in") {
        // With nothing in Health the stepper needs some start; 150 is a generic default.
        pounds = loaded?.prefill ?? 150
        weighing = true
      }
      .font(.system(size: 17, weight: .semibold))
      .accessibilityIdentifier("data.weighIn")
    }
    .foregroundStyle(Theme.text)
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    .task(id: reloads) {
      loaded = await WeeklyWeight.load(from: environment.healthStore, now: environment.now())
    }
    .sheet(isPresented: $weighing) { weighInSheet.presentationDetents([.medium]) }
  }

  private var weighInSheet: some View {
    VStack(spacing: 24) {
      Text(String(format: "%.1f lb", pounds))
        .font(.system(size: Theme.heroNumberSize, weight: .medium))
        .accessibilityIdentifier("data.weighIn.value")
      Stepper("Weight", value: $pounds, in: 50...700, step: 0.1).labelsHidden()
        .accessibilityIdentifier("data.weighIn.stepper")
      Button {
        Task {
          let health = environment.healthStore
          try? await WeeklyWeight.weighIn(pounds: pounds, at: environment.now(), to: health)
          weighing = false
          reloads += 1
        }
      } label: {
        Text("Save").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.invertedText)
          .frame(maxWidth: .infinity, minHeight: 50)
          .background(Theme.invertedCard, in: Capsule())
      }
      .accessibilityIdentifier("data.weighIn.save")
    }
    .padding(24)
    .foregroundStyle(Theme.text)
  }

  private func weekRange(_ start: Date) -> String {
    let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
    let style = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
    return "\(start.formatted(style)) to \(end.formatted(style))"
  }

  private func label(_ text: String) -> some View {
    Text(text).font(.system(size: Theme.labelSize)).foregroundStyle(Theme.label)
  }
}
