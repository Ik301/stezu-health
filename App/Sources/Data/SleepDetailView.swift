import Charts
import StezuCore
import SwiftUI

/// The Sleep screen (S-040, design/system/walkthroughs/data.html): the picked night and the
/// usual one, the 14-night window, the night's stages. Named by wake day; no score (D-032).
struct SleepDetailView: View {
  @Environment(\.appEnvironment) private var environment
  @Environment(\.dismiss) private var dismiss
  @State private var detail: SleepDetail?
  @State private var summary: SleepSummary?  // S-051: the week's mean, as This week's row has it
  @State private var picked: Date?
  @State private var openDay: Date?  // S-047: the picked night's wake day as a day
  private let shape = RoundedRectangle(cornerRadius: Theme.radiusCard)

  init(night: Date? = nil) { _picked = State(initialValue: night) }  // S-041: a wake day picked

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.spaceMd) {
        TopBar(
          title: openDay.map(long) ?? "Sleep", titleID: "sleep.title", action: rung
        )
        .overlay(alignment: .topLeading) {  // S-049: the day arrows in the row above the date
          if let openDay { DayArrows(day: Binding(get: { openDay }, set: { self.openDay = $0 })) }
        }
        if let openDay {  // not Binding($openDay), which crashes when the back rung sets nil
          DayView(day: Binding(get: { openDay }, set: { self.openDay = $0 }))
        } else if let detail, let today = detail.days.last {
          let day = picked ?? today
          let night = detail.nights[day]
          HStack {
            muted(day == today ? "Last night" : long(day)).accessibilityIdentifier("sleep.night")
            if let night { muted("woke \(clock(night.wakeMinutes))") }
          }
          Text(night.map { hm($0.asleep) } ?? "--").textStyle(.big)
            .accessibilityIdentifier("sleep.asleep")
          if let night {
            Text("asleep, in bed \(clock(night.bedMinutes)) to \(clock(night.wakeMinutes))")
          }
          muted("This week avg \(SleepSummary.text(summary?.weekMean.value))")
            .accessibilityIdentifier("sleep.week")
          let usual = "Usual \(detail.usual.map(hm) ?? "--"), your median of \(detail.usualNights)"
          muted(usual + " nights").accessibilityIdentifier("sleep.usual")
          window(detail, day).padding(Theme.spaceLg).background(Theme.surface, in: shape)
          if let night {
            stages(night).padding(Theme.spaceLg).background(Theme.surface, in: shape)
            overnight(detail.overnight[day]).padding(Theme.spaceLg)
              .background(Theme.surface, in: shape)
          }
          Button {
            openDay = day
          } label: {
            HStack {
              Text("\(long(day)) as a day").textStyle(.body).foregroundStyle(Theme.ink)
              Spacer()
              Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, Theme.spaceLg).frame(minHeight: Theme.sizeControl)
            .background(Theme.surface, in: shape).contentShape(shape)
          }
          .accessibilityIdentifier("sleep.asday")
          muted("Nights are named by the morning you woke up. Tracking only: no score, no target.")
            .accessibilityIdentifier("sleep.footer")
        }
      }
      .textStyle(.subtitle).foregroundStyle(Theme.ink).padding(Theme.spaceLg)
    }
    .scrollIndicators(.hidden).background(Theme.ground.ignoresSafeArea())
    .task {
      summary = await SleepSummary.load(from: environment.healthStore, now: environment.now())
      detail = await SleepDetail.load(from: environment.healthStore, now: environment.now())
    }
  }

  /// Done on the night; back to it from its day.
  private var rung: TopBar.Action {
    if openDay != nil { return .init(title: "Sleep", id: "sleep.day.back") { openDay = nil } }
    return .init(title: "Done", id: "sleep.close") { dismiss() }
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
    let ticks = Array(  // every 3 hours on the clock: 00, 03, 06
      stride(from: (axis.lowerBound / 180).rounded(.up) * 180, through: axis.upperBound, by: 180))
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
            ForEach(ticks, id: \.self) {
              Theme.track.frame(width: 1, height: 24).offset(x: x($0, geo.size.width))
            }
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
      GeometryReader { geo in
        ForEach(ticks, id: \.self) {
          Text(clock($0).prefix(2)).textStyle(.axis).foregroundStyle(Theme.muted)
            .position(x: x($0, geo.size.width), y: 8)
        }
      }
      .padding(.horizontal, 55).frame(height: 16)
    }
  }

  /// The hypnogram: a lane per stage with its total on it, then the wake-ups counted.
  private func stages(_ night: SleepNight) -> some View {
    let lane = { (lane: SleepLane) in "\(lane.rawValue) \(hm(night.totals[lane] ?? 0))" }
    let (n, awake) = (night.wakeUps, hm(night.awakeAfterOnset))
    return VStack(alignment: .leading, spacing: Theme.spaceSm) {
      head(
        "Stages, \(night.day.formatted(.dateTime.weekday(.abbreviated).day()))",
        "Estimated by the strap")
      Chart {
        ForEach(SleepLane.allCases, id: \.self) {  // each lane's track in ground
          BarMark(
            xStart: .value("From", night.bedtime), xEnd: .value("To", night.wake),
            y: .value("Stage", lane($0))
          )
          .foregroundStyle(Theme.ground).cornerRadius(5)
        }
        ForEach(Array(night.stages.enumerated()), id: \.offset) { _, stage in
          BarMark(
            xStart: .value("From", stage.start), xEnd: .value("To", stage.end),
            y: .value("Stage", lane(stage.lane)), height: .ratio(0.8)
          )
          .foregroundStyle(Self.color(stage.lane)).cornerRadius(3)
          if stage.lane == .awake {  // a short wake-up is still at least 3 pt wide
            RectangleMark(
              x: .value("At", stage.start + stage.end.timeIntervalSince(stage.start) / 2),
              y: .value("Stage", lane(stage.lane)), width: .fixed(3), height: .ratio(0.8)
            ).foregroundStyle(Self.color(stage.lane))
          }
        }
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

  /// Heart rate in data-heart, breathing and HRV in ink, each "--" when the strap has none.
  private func overnight(_ overnight: Overnight?) -> some View {
    VStack(alignment: .leading, spacing: Theme.spaceSm) {
      head("Overnight", "")
      HStack(alignment: .top) {
        ForEach(overnight?.line ?? [], id: \.id) { reading in
          VStack(alignment: .leading, spacing: Theme.space2xs) {
            muted(reading.name)
            HStack(alignment: .firstTextBaseline, spacing: Theme.space2xs) {
              Text(reading.value).textStyle(.value)
                .foregroundStyle(reading.id == "heartRate" ? Theme.dataHeart : Theme.ink)
              muted(reading.unit)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .ignore)
          .accessibilityLabel(
            [reading.name, reading.value, reading.unit].filter { !$0.isEmpty }.joined(
              separator: " ")
          )
          .accessibilityIdentifier("sleep.overnight.\(reading.id)")
        }
      }
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
  static func color(_ lane: SleepLane) -> Color {
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
