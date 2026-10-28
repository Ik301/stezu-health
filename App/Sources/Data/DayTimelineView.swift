import StezuCore
import SwiftUI

/// S-041, components/DayTimeline. Left: visits by name (S-049) or their times. Right: the night,
/// weigh-ins, meals and workouts, in lanes where they overlap. Empty hours fold to a thin band,
/// with a dashed line where a fold starts. Under a "Where / What" header.
struct DayTimelineView: View {
  struct Mark {
    let id, title, detail: String
    let span: DateInterval
    var stripe: [Gradient.Stop] = []  // down the left edge
    let tap: () -> Void
  }

  /// S-049: a visit and its name from the phone's cache; nil shows its times only.
  struct Visit {
    let span: DateInterval
    let name: String?
  }

  let day: Date
  let marks: [Mark]
  let visits: [Visit]
  private let gutter: CGFloat = 36
  private let column: CGFloat = 80
  private let namedTimes: CGFloat = 56  // tall enough for a name's two lines and its times

  var body: some View {
    let timeline = DayTimeline(day: day, spans: marks.map(\.span))
    let hour = { (hour: Int) in timeline.y(timeline.start + Double(hour) * 3600) }
    let open = { (h: Int) in h == 24 || timeline.hours[h] == DayTimeline.fullHour }
    let labelled = (0...24).filter { open($0) && ($0 % 3 == 0 || ($0 > 0 && !open($0 - 1))) }
    let folds = (1..<24).filter { !open($0) && open($0 - 1) }  // a dashed line where a fold starts
    GeometryReader { geo in
      let left = gutter + column + Theme.spaceSm
      ZStack(alignment: .topLeading) {
        ForEach(labelled, id: \.self) { h in
          Text(String(format: "%02d", h)).textStyle(.axis).foregroundStyle(Theme.muted)
            .offset(y: hour(h) - Theme.spaceSm).accessibilityIdentifier("day.timeline.hour.\(h)")
          Rectangle().fill(Theme.track).frame(width: geo.size.width - gutter, height: 1)
            .offset(x: gutter, y: hour(h))
        }
        ForEach(folds, id: \.self) { h in
          Path { $0.addLines([.zero, CGPoint(x: geo.size.width - gutter, y: 0)]) }
            .stroke(Theme.track, style: StrokeStyle(lineWidth: 1, dash: [Theme.spaceXs]))
            .frame(height: 1).offset(x: gutter, y: hour(h))
        }
        ForEach(Array(visits.enumerated()), id: \.offset) { index, visit in
          let top = timeline.y(visit.span.start)
          let height = max(Theme.spaceXl, timeline.y(visit.span.end) - top - Theme.spaceXs)
          let times = "\(Self.clock(visit.span.start))–\(Self.clock(visit.span.end))"
          VStack(alignment: .leading, spacing: 0) {
            if let name = visit.name { Text(name).textStyle(.label).lineLimit(2) }
            if visit.name == nil || height > namedTimes {
              Text(times).textStyle(visit.name == nil ? .label : .axis)
                .foregroundStyle(visit.name == nil ? Theme.ink : Theme.muted)
            }
          }
          .foregroundStyle(Theme.ink).padding(Theme.spaceXs)
          .frame(width: column, height: height, alignment: .topLeading)
          .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.radiusChip))
          .clipped().offset(x: gutter, y: top + Theme.space2xs)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(visit.name.map { "\($0), \(times)" } ?? times)
          .accessibilityIdentifier("day.timeline.visit.\(index)")
        }
        ForEach(Array(marks.enumerated()), id: \.offset) { index, mark in
          if let placed = timeline.marks[index] {
            let width = (geo.size.width - left) / CGFloat(placed.lanes)
            card(mark, height: placed.height - Theme.spaceXs).frame(width: width - Theme.space2xs)
              .offset(x: left + CGFloat(placed.lane) * width, y: placed.top + Theme.space2xs)
          }
        }
      }
    }
    .frame(height: timeline.height).padding(.top, Theme.spaceXl)
    .overlay(alignment: .topLeading) {
      HStack(spacing: Theme.spaceSm) {
        Text("Where").frame(width: column, alignment: .leading)
        Text("What")
      }
      .textStyle(.label).foregroundStyle(Theme.muted).padding(.leading, gutter)
    }
  }

  private func card(_ mark: Mark, height: CGFloat) -> some View {
    let shape = RoundedRectangle(cornerRadius: Theme.radiusInner)
    return Button(action: mark.tap) {
      VStack(alignment: .leading, spacing: 0) {
        Text(mark.title).textStyle(.label, weight: .semibold).foregroundStyle(Theme.ink)
        Text(mark.detail).textStyle(.label).foregroundStyle(Theme.muted)
      }
      .padding(.vertical, Theme.spaceXs).padding(.horizontal, Theme.spaceMd)
      .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
      .background(alignment: .leading) {
        if !mark.stripe.isEmpty {
          LinearGradient(stops: mark.stripe, startPoint: .top, endPoint: .bottom).frame(width: 6)
        }
      }
      .background(Theme.surface, in: shape).clipShape(shape)
      .overlay(shape.stroke(Theme.edge, lineWidth: 1))
    }
    .buttonStyle(.plain).accessibilityIdentifier(mark.id)
  }

  static func clock(_ date: Date) -> String {
    let time = Calendar.current.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", time.hour ?? 0, time.minute ?? 0)
  }
}
