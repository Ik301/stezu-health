import StezuCore
import SwiftUI

/// Sources (S-020): one row per Health type with its last sample, the apps that wrote it in the
/// last 7 days and how many samples each, the hint for denied reads, and the writes that did not
/// reach Health. An absent type shows "--", never 0.
struct SourcesView: View {
  let store: any HealthStore
  /// Writes Health refused. Nothing writes yet; the write stories append here.
  var failedWrites: [String] = []
  @State private var rows: [HealthTypeSummary]?
  @Environment(\.dismiss) private var dismiss

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
        ForEach(rows ?? [], id: \.type) { row($0) }
        Text("Not in Health").font(.system(size: 17, weight: .semibold))
          .accessibilityIdentifier("sources.notInHealth")
        label(failedWrites.isEmpty ? "None" : failedWrites.joined(separator: "\n"))
      }
      .padding(16)
      .foregroundStyle(Theme.text)
    }
    .background(Theme.background.ignoresSafeArea())
    .task { rows = await HealthSources.load(from: store) }
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
          + (sources.isEmpty ? "" : " (\(sources.joined(separator: ", ")))"))
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
