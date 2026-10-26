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
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Sources")
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(Theme.text)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("screen.sources.title")
          Spacer()
          Button("Done") { dismiss() }
            .foregroundStyle(Theme.text)
            .accessibilityIdentifier("sources.done")
        }
        locationRow
        ForEach(rows ?? [], id: \.type) { row($0) }
        Text("Not in Health").font(.system(size: 17, weight: .semibold))
          .accessibilityIdentifier("sources.notInHealth")
        label(failedWrites.isEmpty ? "None" : failedWrites.joined(separator: "\n"))
      }
      .padding(16)
      .foregroundStyle(Theme.text)
    }
    .scrollIndicators(.hidden)
    .background(Theme.background.ignoresSafeArea())
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
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("Location").font(.system(size: 17, weight: .semibold))
        Spacer()
        if let permission = location?.0, permission != .always {
          Button("Allow") { Task { await environment.locationSource.requestAccess() } }
            .accessibilityIdentifier("sources.location.allow")
        }
        Text(location?.0.rawValue ?? "--").accessibilityIdentifier("sources.location.status")
      }
      .font(.system(size: 17, weight: .medium))
      label(
        "Last location: \(location?.1?.formatted(date: .abbreviated, time: .shortened) ?? "--")"
      )
      .accessibilityIdentifier("sources.location.last")
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
  }

  private func row(_ summary: HealthTypeSummary) -> some View {
    let id = "sources.row.\(summary.type)"
    let sources = summary.recentSources.map { "\($0.name) \($0.count)" }
    return VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(summary.type.rawValue).font(.system(size: 17, weight: .semibold))
        Spacer()
        Text(summary.isPresent ? "Present" : "--")
          .font(.system(size: 17, weight: .medium))
          .accessibilityIdentifier("\(id).status")
      }
      .foregroundStyle(Theme.text)
      label("Last sample: \(summary.lastSampleDate?.formatted(.dateTime) ?? "--")")
      label(
        "Last 7 days: \(summary.recentSampleCount.map { "\($0) samples" } ?? "--")"
          + (sources.isEmpty ? "" : " (\(sources.joined(separator: ", ")))")
      ).accessibilityIdentifier("\(id).recent")
      if !summary.isPresent {
        label(HealthSources.deniedHint).accessibilityIdentifier("\(id).hint")
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
  }

  private func label(_ text: String) -> some View {
    Text(text).font(.system(size: Theme.labelSize)).foregroundStyle(Theme.label)
  }
}
