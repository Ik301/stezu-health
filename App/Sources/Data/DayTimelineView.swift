import StezuCore
import SwiftUI

/// S-041, components/DayTimeline. Left: visits and their times. Right: the night, weigh-ins,
/// meals and workouts, in lanes where they overlap. Empty hours fold to a thin band.
struct DayTimelineView: View {
  struct Mark {
    let id, title, detail: String
    let span: DateInterval
    var stripe: [Gradient.Stop] = []  // down the left edge
    let tap: () -> Void
  }

  let day: Date
  let marks: [Mark]
  let visits: [DateInterval]
  private let gutter: CGFloat = 36
  private let column: CGFloat = 80

  var body: some View {
    let timeline = DayTimeline(day: day, spans: marks.map(\.span))
    let hour = { (hour: Int) in timeline.y(timeline.start + Double(hour) * 3600) }
    let open = { (h: Int) in h == 24 || timeline.hours[h] == DayTimeline.fullHour }
    let labelled = (0...24).filter { open($0) && ($0 % 3 == 0 || ($0 > 0 && !open($0 - 1))) }
    GeometryReader { geo in
      let left = gutter + column + Theme.spaceSm
      ZStack(alignment: .topLeading) {
        ForEach(labelled, id: \.self) { h in
          Text(String(format: "%02d", h)).textStyle(.axis).foregroundStyle(Theme.muted)
            .offset(y: hour(h) - Theme.spaceSm).accessibilityIdentifier("day.timeline.hour.\(h)")
          Rectangle().fill(Theme.track).frame(width: geo.size.width - gutter, height: 1)
            .offset(x: gutter, y: hour(h))
        }
        ForEach(Array(visits.enumerated()), id: \.offset) { index, visit in
          let top = timeline.y(visit.start)
          Text("\(Self.clock(visit.start))–\(Self.clock(visit.end))").textStyle(.label)
            .foregroundStyle(Theme.ink).padding(Theme.spaceXs)
            .frame(
              width: column,
              height: max(Theme.spaceXl, timeline.y(visit.end) - top - Theme.spaceXs),
              alignment: .topLeading
            )
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.radiusChip))
            .clipped().offset(x: gutter, y: top + Theme.space2xs)
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
    .frame(height: timeline.height)
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
