import StezuCore
import SwiftUI

/// This week's steps, sleep, HRV and resting heart rate, each with its coverage (S-022); sleep and
/// HRV are labelled context. No data shows "--" beside its coverage, never 0, plus the hint.
struct WeeklyHealthRows: View {
  @Environment(\.appEnvironment) private var environment
  @State private var week: WeeklyHealth?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      row("Steps", "steps", week?.steps, of: "days") { "\(Int($0.rounded()))" }
      row("Sleep", "sleep", week?.sleep, of: "nights", context: true) {
        "\(Int($0 / 3600))h \(Int($0 / 60) % 60)m"
      }
      row("HRV", "hrv", week?.hrv, of: nil, context: true) { "\(Int($0.rounded())) ms" }
      row("Resting HR", "restingHR", week?.restingHeartRate, of: "days") {
        "\(Int($0.rounded())) bpm"
      }
      if let week,
        [week.steps, week.sleep, week.hrv, week.restingHeartRate].contains(where: {
          $0.value == nil
        })
      {
        label(HealthSources.deniedHint).accessibilityIdentifier("data.health.hint")
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    .task { week = await WeeklyHealth.load(from: environment.healthStore, now: environment.now()) }
  }

  /// Coverage reads "n of 7 <unit>", or "n samples" when `unit` is nil.
  private func row(
    _ title: String, _ id: String, _ stat: WeeklyStat?, of unit: String?, context: Bool = false,
    format: (Double) -> String
  ) -> some View {
    let coverage =
      stat.map { stat in unit.map { "\(stat.coverage) of 7 \($0)" } ?? "\(stat.coverage) samples" }
    let value = stat?.value.map(format) ?? "--"
    return HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(title).font(.system(size: 17, weight: .semibold))
          if context { label("context").accessibilityIdentifier("data.\(id).context") }
        }
        label(coverage ?? "--").accessibilityIdentifier("data.\(id).coverage")
      }
      Spacer()
      Text(value).font(.system(size: 17, weight: .medium)).accessibilityIdentifier(
        "data.\(id).value")
    }
    .foregroundStyle(Theme.text)
  }

  private func label(_ text: String) -> some View {
    Text(text).font(.system(size: Theme.labelSize)).foregroundStyle(Theme.label)
  }
}
