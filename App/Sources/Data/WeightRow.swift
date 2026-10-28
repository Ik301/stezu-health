import StezuCore
import SwiftUI

/// This Monday-to-Sunday week's dates, then the Body and activity card (S-021, S-039): Weight
/// and Steps rows, and Weigh in, which opens a stepper prefilled with the last weigh-in; Save
/// stores a weigh-in and reloads the rows.
struct BodyCard: View {
  var open: (Metric) -> Void = { _ in }
  @Environment(\.appEnvironment) private var environment
  @State private var loaded: (week: WeekWeight, prefill: Double?)?
  @State private var weighing = false
  @State private var reloads = 0

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spaceMd) {
      label(weekRange(WeeklyStats.week(containing: environment.now()).start))
        .accessibilityIdentifier("data.week.range")
      MetricCard(
        title: "Body and activity",
        action: .init(title: "Weigh in", id: "data.weighIn") { weighing = true }
      ) {
        WeeklyHealthRows(metrics: [.weight, .steps], reload: reloads, open: open)
      }
    }
    .task(id: reloads) {
      loaded = await WeeklyWeight.load(from: environment.weightHealth, now: environment.now())
    }
    .sheet(isPresented: $weighing) {
      // With nothing in Health the stepper needs some start; 150 is a generic default.
      WeighInSheet(pounds: loaded?.prefill ?? 150) { reloads += 1 }
        .presentationDetents([.medium]).presentationDragIndicator(.visible)
    }
  }

  private func weekRange(_ start: Date) -> String {
    let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
    let style = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
    return "\(start.formatted(style)) to \(end.formatted(style))"
  }

  private func label(_ text: String) -> some View {
    Text(text).textStyle(.label).foregroundStyle(Theme.muted)
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
    VStack(spacing: Theme.spaceXl) {
      TopBar(
        title: "Weigh-in", titleID: "data.weighIn.title",
        action: .init(title: "Done", id: "data.weighIn.done") { dismiss() })
      Text(String(format: "%.1f lb", pounds))
        .textStyle(.hero)
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
        Text("Save").textStyle(.headline).foregroundStyle(Theme.onInvert)
          .frame(maxWidth: .infinity, minHeight: 50)
          .background(Theme.invert, in: Capsule())
      }
      .accessibilityIdentifier("data.weighIn.save")
    }
    .padding(Theme.spaceXl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .foregroundStyle(Theme.ink)
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
