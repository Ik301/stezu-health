import Foundation
import StezuCore
import SwiftUI
import WidgetKit

// The home-screen widgets' entry and views (S-060). Compiled into the extension, which draws them
// on the home screen, and into the app, whose `-uitest-widgets` gallery draws them for UI tests.

/// One reload of a surface widget. With no reply and nothing cached, `today` is empty, so every
/// field shows "--".
struct SurfaceEntry: TimelineEntry, Sendable {
  var date: Date
  var today = SurfaceToday()
  /// "Saved <date>" when the server didn't answer and the cached copy is from an earlier day.
  var savedNote: String?

  /// Fetch through the cache, and say when to reload next (after midnight, or a retry).
  static func load(with fetcher: CachedPayloadFetcher, now: Date = .now) async -> (
    entry: SurfaceEntry, next: Date
  ) {
    let fetched = await fetcher.fetch(SurfaceToday.self, path: SurfaceToday.path)
    let today = fetched?.value ?? SurfaceToday()
    let note = today.savedNote(isCached: fetched?.isCached ?? false, now: now, calendar: .current)
    let next = SurfaceToday.nextReload(
      after: now, fetched: fetched?.isCached == false, calendar: .current)
    return (SurfaceEntry(date: now, today: today, savedNote: note), next)
  }
}

/// The Word widget: the word on one line, then its definition, cut with an ellipsis to fit.
struct WordWidgetView: View {
  let entry: SurfaceEntry
  let family: WidgetFamily

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spaceXs) {
      Text("Word").textStyle(.label).foregroundStyle(Theme.muted)
      Text(entry.today.wordText)
        .textStyle(family == .systemSmall ? .title2 : .stat)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .layoutPriority(1)
        .accessibilityIdentifier("widget.word.word")
      Text(entry.today.definitionText)
        .textStyle(family == .systemSmall ? .subtitle : .body)
        .lineLimit(family == .systemSmall ? 4 : 3)
        .truncationMode(.tail)
        .accessibilityIdentifier("widget.word.definition")
      Spacer(minLength: 0)
      SavedNoteView(note: entry.savedNote)
    }
    .foregroundStyle(Theme.ink)
    .frame(maxWidth: .infinity, alignment: .leading)
    .containerBackground(Theme.surface, for: .widget)
  }
}

/// The "Saved <date>" line under a widget's content, shown only for an earlier day's copy.
struct SavedNoteView: View {
  let note: String?

  var body: some View {
    if let note {
      Text(note)
        .textStyle(.label)
        .foregroundStyle(Theme.muted)
        .lineLimit(1)
        .layoutPriority(1)
        .accessibilityIdentifier("widget.saved")
    }
  }
}
