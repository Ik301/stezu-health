import StezuCore
import SwiftUI

/// Sources (S-020): one row per Health type with its last sample, the apps that wrote it in the
/// last 7 days and how many samples each, the hint for denied reads, and the writes that did not
/// reach Health. An absent type shows "--", never 0.
struct SourcesView: View {
  let store: any HealthStore
  /// Writes Health refused. Nothing writes yet; the write stories append here.
  var failedWrites: [String] = []
  /// The end of the 7-day window: the clock, or the scenario's synthetic Sunday.
  var now = Date()
  @State private var rows: [HealthTypeSummary]?
  @State private var location: (LocationPermission, Date?)?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.appEnvironment) private var environment

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.spaceMd) {
        HStack {
          Text("Sources")
            .textStyle(.title1)
            .foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("screen.sources.title")
          Spacer()
          Button("Done") { dismiss() }
            .foregroundStyle(Theme.ink)
            .accessibilityIdentifier("sources.done")
        }
        locationRow
        ForEach(rows ?? [], id: \.type) { row($0) }
        Text("Not in Health").textStyle(.headline)
          .accessibilityIdentifier("sources.notInHealth")
        label(failedWrites.isEmpty ? "None" : failedWrites.joined(separator: "\n"))
      }
      .padding(Theme.spaceLg)
      .foregroundStyle(Theme.ink)
    }
    .scrollIndicators(.hidden)
    .background(Theme.ground.ignoresSafeArea())
    .task { rows = await HealthSources.load(from: store, now: now) }
    .task {  // S-032: live while open, so Allow's answer and new fixes show
      while !Task.isCancelled {
        let permission = await environment.locationSource.permission()
        location = (permission, await environment.places.log.places.flatMap(\.times).max())
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }

  /// S-032: the permission, the last location's time or "--", and Allow until Always.
  private var locationRow: some View {
    VStack(alignment: .leading, spacing: Theme.spaceXs) {
      HStack {
        Text("Location").textStyle(.headline)
        Spacer()
        if let permission = location?.0, permission != .always {
          Button("Allow") { Task { await environment.locationSource.requestAccess() } }
            .accessibilityIdentifier("sources.location.allow")
        }
        Text(location?.0.rawValue ?? "--").accessibilityIdentifier("sources.location.status")
      }
      .textStyle(.value)
      label(
        "Last location: \(location?.1?.formatted(date: .abbreviated, time: .shortened) ?? "--")"
      )
      .accessibilityIdentifier("sources.location.last")
    }
    .padding(Theme.spaceMd)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
  }

  private func row(_ summary: HealthTypeSummary) -> some View {
    let id = "sources.row.\(summary.type)"
    let sources = summary.recentSources.map { "\($0.name) \($0.count)" }
    return VStack(alignment: .leading, spacing: Theme.spaceXs) {
      HStack {
        Text(summary.type.rawValue).textStyle(.headline)
        Spacer()
        Text(summary.isPresent ? "Present" : "--")
          .textStyle(.value)
          .accessibilityIdentifier("\(id).status")
      }
      .foregroundStyle(Theme.ink)
      label("Last sample: \(summary.lastSampleDate?.formatted(.dateTime) ?? "--")")
      label(
        "Last 7 days: \(summary.recentSampleCount.map { "\($0) samples" } ?? "--")"
          + (sources.isEmpty ? "" : " (\(sources.joined(separator: ", ")))")
      ).accessibilityIdentifier("\(id).recent")
      if !summary.isPresent {
        label(HealthSources.deniedHint).accessibilityIdentifier("\(id).hint")
      }
    }
    .padding(Theme.spaceMd)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
  }

  private func label(_ text: String) -> some View {
    Text(text).textStyle(.label).foregroundStyle(Theme.muted)
  }
}
