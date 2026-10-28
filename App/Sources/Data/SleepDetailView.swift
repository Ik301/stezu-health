import Charts
import StezuCore
import SwiftUI

/// The Sleep screen (S-040, design/system/walkthroughs/data.html): the picked night and the
/// usual one, the 14-night window, the night's stages. Named by wake day; no score (D-032).
struct SleepDetailView: View {
  @Environment(\.appEnvironment) private var environment
  @Environment(\.dismiss) private var dismiss
  @State private var detail: SleepDetail?
  @State private var picked: Date?
  private let shape = RoundedRectangle(cornerRadius: Theme.radiusCard)

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.spaceMd) {
        TopBar(
          title: "Sleep", titleID: "sleep.title",
          action: TopBar.Action(title: "Done", id: "sleep.close") { dismiss() })
        if let detail, let today = detail.days.last {
          let day = picked ?? today
          let night = detail.nights[day]
          muted(day == today ? "Last night" : long(day)).accessibilityIdentifier("sleep.night")
          Text(night.map { hm($0.asleep) } ?? "--").textStyle(.big)
            .accessibilityIdentifier("sleep.asleep")
          if let night {
            Text("asleep, in bed \(clock(night.bedMinutes)) to \(clock(night.wakeMinutes))")
          }
          let usual = "Usual \(detail.usual.map(hm) ?? "--"), your median of \(detail.usualNights)"
          muted(usual + " nights").accessibilityIdentifier("sleep.usual")
          window(detail, day).padding(Theme.spaceLg).background(Theme.surface, in: shape)
          if let night { stages(night).padding(Theme.spaceLg).background(Theme.surface, in: shape) }
          muted("Nights are named by the morning you woke up. Tracking only: no score, no target.")
            .accessibilityIdentifier("sleep.footer")
        }
      }
      .textStyle(.subtitle).foregroundStyle(Theme.ink).padding(Theme.spaceLg)
    }
    .scrollIndicators(.hidden).background(Theme.ground.ignoresSafeArea())
    .task { detail = await SleepDetail.load(from: environment.healthStore, now: environment.now()) }
  }

  /// Bedtime to final wake per night on one clock axis; usual lines labelled; picked in ink.
  private func window(_ detail: SleepDetail, _ picked: Date) -> some View {
    let axis = detail.axis
    let x = { (minutes: Double, width: CGFloat) in
      width * (min(max(minutes, axis.lowerBound), axis.upperBound) - axis.lowerBound)
        / (axis.upperBound - axis.lowerBound)
    }
    let usual = [detail.usualBed.map { ($0, "usual ") }, detail.usualWake.map { ($0, "") }]
      .compactMap { $0 }
    return VStack(spacing: 0) {
      head("Sleep window", "\(detail.nights.count) of \(SleepDetail.windowNights) nights")
      GeometryReader { geo in
        ForEach(usual, id: \.0) { minutes, prefix in
          Text(prefix + clock(minutes)).textStyle(.axis).fixedSize()
            .position(x: x(minutes, geo.size.width) + (prefix.isEmpty ? 20 : -36), y: 10)
        }
      }
      .padding(.horizontal, 55).frame(height: 20)
      ForEach(Array(detail.days.enumerated()), id: \.offset) { index, day in
        let (night, on) = (detail.nights[day], day == picked)
        HStack(spacing: 0) {
          Text(day, format: .dateTime.weekday(.abbreviated).day()).frame(
            width: 55, alignment: .leading)
          GeometryReader { geo in
            ForEach(usual, id: \.0) { minutes, _ in
              Path { $0.addLines([.zero, CGPoint(x: 0, y: 24)]) }
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .offset(x: x(minutes, geo.size.width))
            }
            if let night {
              let start = x(night.bedMinutes, geo.size.width)
              Capsule().fill(on ? Theme.ink : Theme.dataSample)
                .frame(width: max(2, x(night.wakeMinutes, geo.size.width) - start), height: 12)
                .offset(x: start, y: 6)
            }
          }
          Text(night.map { hm($0.asleep) } ?? "--").frame(width: 55, alignment: .trailing)
            .accessibilityIdentifier("sleep.window.\(index).value")
        }
        .textStyle(.label, weight: on ? .semibold : nil).frame(height: 24)
        .foregroundStyle(on ? Theme.ink : Theme.muted)
        .overlay {
          if let night {
            Button(action: { self.picked = day }) { Color.clear.contentShape(Rectangle()) }
              .accessibilityLabel("\(long(day)), \(hm(night.asleep)) asleep")
              .accessibilityIdentifier("sleep.window.\(index)")
          }
        }
      }
    }
  }

  /// The hypnogram: a lane per stage with its total on it, then the wake-ups counted.
  private func stages(_ night: SleepNight) -> some View {
    let lane = { (lane: SleepLane) in "\(lane.rawValue) \(hm(night.totals[lane] ?? 0))" }
    let (n, awake) = (night.wakeUps, hm(night.awakeAfterOnset))
    return VStack(alignment: .leading, spacing: Theme.spaceSm) {
      head("Stages", "Estimated by the strap")
      Chart(Array(night.stages.enumerated()), id: \.offset) { _, stage in
        BarMark(
          xStart: .value("From", stage.start), xEnd: .value("To", stage.end),
          y: .value("Stage", lane(stage.lane))
        )
        .foregroundStyle(color(stage.lane)).cornerRadius(3)
      }
      .chartYScale(domain: SleepLane.allCases.map(lane))
      .chartYAxis { AxisMarks(position: .leading) }
      .chartXScale(domain: night.bedtime...night.wake).frame(height: 120)
      .accessibilityIdentifier("sleep.stages")
      muted(
        (n == 0 ? "No wake-ups" : "\(n) wake-up\(n == 1 ? "" : "s"), \(awake) awake")
          + " after falling asleep"
      )
      .accessibilityIdentifier("sleep.wakeups")
    }
  }

  private func head(_ title: String, _ detail: String) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(detail).foregroundStyle(Theme.muted)
    }.textStyle(.label)
  }

  private func muted(_ text: String) -> some View {
    Text(text).textStyle(.label).foregroundStyle(Theme.muted)
  }

  /// sleep-awake, the one warm hue, then REM to Deep from light to dark.
  private func color(_ lane: SleepLane) -> Color {
    [Theme.sleepAwake, Theme.sleepRem, Theme.sleepCore, Theme.sleepDeep][
      SleepLane.allCases.firstIndex(of: lane) ?? 0]
  }

  private func long(_ day: Date) -> String {
    day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
  }

  private func hm(_ seconds: TimeInterval) -> String {
    let minutes = Int((seconds / 60).rounded())
    return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
  }

  /// Minutes from the wake day's midnight as "23:45".
  private func clock(_ minutes: Double) -> String {
    let wrapped = (Int(minutes.rounded()) % 1440 + 1440) % 1440
    return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
  }
}
