import StezuCore
import SwiftUI

/// The overview's Weight row for this Monday-to-Sunday week (S-021): trend, the trend's change
/// this week, weigh-in days out of 7, the confidence reason and the apps the trend uses. Weigh in
/// opens a stepper prefilled with the last weigh-in; Save stores a weigh-in and reloads the row.
struct WeightRow: View {
  var open: (Metric) -> Void = { _ in }
  @Environment(\.appEnvironment) private var environment
  @State private var loaded: (week: WeekWeight, prefill: Double?)?
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
        MetricOpenButton(metric: .weight, open: open)
      }
      label("This week: " + (week?.change.map { String(format: "%+.1f lb", $0) } ?? "--"))
        .accessibilityIdentifier("data.weight.change")
      label("Weigh-ins: " + (week?.daysWeighed.map { "\($0) of 7" } ?? "--"))
        .accessibilityIdentifier("data.weight.coverage")
      label(week?.confidence.reason ?? "--").accessibilityIdentifier("data.weight.reason")
      label("From: " + (sources.isEmpty ? "--" : sources)).accessibilityIdentifier(
        "data.weight.sources")
      Button("Weigh in") { weighing = true }
        .font(.system(size: 17, weight: .semibold))
        .accessibilityIdentifier("data.weighIn")
    }
    .foregroundStyle(Theme.text)
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    .task(id: reloads) {
      loaded = await WeeklyWeight.load(from: environment.weightHealth, now: environment.now())
    }
    .sheet(isPresented: $weighing) {
      // With nothing in Health the stepper needs some start; 150 is a generic default.
      WeighInSheet(pounds: loaded?.prefill ?? 150) { reloads += 1 }
        .presentationDetents([.medium])
    }
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

/// The weigh-in stepper: starts at the prefill, 0.1 lb steps, no keyboard. Save writes one sample.
private struct WeighInSheet: View {
  @State private var pounds: Double
  private let saved: () -> Void
  @Environment(\.appEnvironment) private var environment
  @Environment(\.dismiss) private var dismiss

  init(pounds: Double, saved: @escaping () -> Void) {
    _pounds = State(initialValue: pounds)
    self.saved = saved
  }

  var body: some View {
    VStack(spacing: 24) {
      Text(String(format: "%.1f lb", pounds))
        .font(.system(size: Theme.heroNumberSize, weight: .medium))
        .accessibilityIdentifier("data.weighIn.value")
      Stepper("Weight", value: $pounds, in: 50...700, step: 0.1).labelsHidden()
        .accessibilityIdentifier("data.weighIn.stepper")
      Button {
        Task {
          await environment.weighIn(pounds: pounds)
          dismiss()
          saved()
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
}

/// S-031: weigh-ins.json, next to finished-workouts.json; memory storage keeps it for the launch.
enum WeighInFile {
  static func store(storage: StorageMode) -> WeighInStore {
    let file = FinishedWorkoutStore(storage: storage).file?.deletingLastPathComponent()
      .appendingPathComponent("weigh-ins.json")
    let saved = file.flatMap { try? Data(contentsOf: $0) }
      .flatMap { try? JSONDecoder().decode(WeighInLog.self, from: $0) }
    return WeighInStore(log: saved ?? WeighInLog()) { log in
      guard let file, let data = try? JSONEncoder().encode(log) else { return }
      try? FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: file, options: .atomic)
    }
  }
}

extension AppEnvironment {
  /// Health with Stezu's weigh-ins from the store; the first read once connected imports Health's.
  var weightHealth: any HealthStore {
    WeighInHealth(
      base: healthStore, store: weighIns, migrates: isUITest || healthConnection.isConnected
    ) { await self.syncRecords($0) }
  }

  func weighIn(pounds: Double) async {
    await weighIns.add(pounds: pounds, at: now(), health: healthStore) {
      await self.syncRecords($0)
    }
  }

  func deleteWeighIn(at date: Date) async {
    await weighIns.delete(at: date, health: healthStore) { await self.syncRecords($0) }
  }

  /// Sources' "Not in Health": the weigh-ins Health refused.
  func weighInsNotInHealth() async -> [String] {
    await weighIns.notInHealth().map { "Weigh-in \($0.measuredAt.formatted()), \($0.pounds) lb" }
  }
}
