import SwiftUI

/// A This week row (design/system/components/MetricRow): title, coverage, a 72 x 28 Sparkline,
/// value and chevron, under a track rule unless `first`. The whole row (44 pt or more) is one
/// button laid over the content (`data.<id>.open`), so the texts keep their ids (D-115).
struct MetricRow: View {
  let title, id, coverage: String
  let values: [Double?]
  var bars = true
  var color = Theme.ink
  let value: String
  var unit: String?  // S-051: a small muted word after the value, as Sleep's "avg"
  var first = false
  var open: (() -> Void)?
  @Environment(\.appEnvironment) private var environment
  private var text: String { [value, unit].compactMap { $0 }.joined(separator: " ") }

  var body: some View {
    let days = values.isEmpty ? Array(repeating: nil, count: 7) : values
    HStack(spacing: Theme.spaceSm) {
      VStack(alignment: .leading, spacing: Theme.space2xs) {
        Text(title).textStyle(.headline)
        Text(coverage).textStyle(.label).foregroundStyle(Theme.muted)
          .accessibilityIdentifier("data.\(id).coverage")
      }
      Spacer(minLength: Theme.spaceXs)
      Sparkline(
        title: title, values: days, bars: bars, color: color,
        today: (Calendar.current.component(.weekday, from: environment.now()) + 5) % 7
      )
      .accessibilityValue("\(days.filter { $0 == nil }.count) of 7 days without data")
      .accessibilityIdentifier("data.spark.\(id)")
      HStack(alignment: .firstTextBaseline, spacing: Theme.space2xs) {
        Text(value).textStyle(.value)
        if let unit { Text(unit).textStyle(.label).foregroundStyle(Theme.muted) }
      }
      .accessibilityElement(children: .ignore).accessibilityLabel(text)
      .accessibilityIdentifier("data.\(id).value")
      if open != nil {
        Image(systemName: "chevron.right").textStyle(.subtitle, weight: .semibold)
          .foregroundStyle(Theme.muted)
      }
    }
    // The row button says it all, so VoiceOver reads the row once; tests still see the parts.
    .accessibilityHidden(open != nil && !environment.isUITest)
    .frame(minHeight: Theme.sizeTarget).padding(.vertical, Theme.spaceSm)
    .overlay(alignment: .top) { if !first { Theme.track.frame(height: 1) } }
    .overlay {
      if let open {
        Button(action: open) { Color.clear.contentShape(Rectangle()) }
          .accessibilityLabel("\(title), \(coverage), \(text)")
          .accessibilityIdentifier("data.\(id).open")
      }
    }
  }
}

/// A This week card: a header, with a tag or one text action on the right, then its rows.
struct MetricCard<Content: View>: View {
  let title: String
  var tag: String?
  var action: TopBar.Action?
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(title).foregroundStyle(Theme.muted).accessibilityAddTraits(.isHeader)
        Spacer()
        if let tag {
          Text(tag).foregroundStyle(Theme.muted).padding(.horizontal, Theme.spaceSm)
            .overlay(Capsule().stroke(Theme.track)).accessibilityIdentifier("data.card.tag")
        }
        if let action {
          Button(action.title, action: action.run).accessibilityIdentifier(action.id)
        }
      }
      .textStyle(.label).buttonStyle(.plain).frame(minHeight: Theme.sizeTarget)
      content
    }
    .foregroundStyle(Theme.ink).padding(.horizontal, Theme.spaceLg)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
  }
}
