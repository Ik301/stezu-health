import Foundation
import StezuCore
import SwiftUI
import WidgetKit

// The home-screen widgets' entry and views (S-060, S-061, S-062). Compiled into the extension, which draws them
// on the home screen, and into the app, whose `-uitest-widgets` gallery draws them for UI tests.

/// One reload of a surface widget. With no reply and nothing cached, `today` is empty, so every
/// field shows "--".
struct SurfaceEntry: TimelineEntry, Sendable {
  var date: Date
  var today = SurfaceToday()
  /// "Saved <date>" when the server didn't answer and the cached copy is from an earlier day.
  var savedNote: String?

  /// Fetch through the cache, and say when to reload next: after midnight or a retry, or every
  /// 45 minutes for the Tasks widget (`frequent`).
  static func load(with fetcher: CachedPayloadFetcher, frequent: Bool = false, now: Date = .now)
    async -> (entry: SurfaceEntry, next: Date)
  {
    let fetched = await fetcher.fetch(SurfaceToday.self, path: SurfaceToday.path)
    let today = fetched?.value ?? SurfaceToday()
    let note = today.savedNote(isCached: fetched?.isCached ?? false, now: now, calendar: .current)
    let next =
      frequent
      ? SurfaceToday.nextTasksReload(after: now, calendar: .current)
      : SurfaceToday.nextReload(after: now, fetched: fetched?.isCached == false, calendar: .current)
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

/// The Goal widget (S-061): the current goals, up to three, each cut with an ellipsis to fit.
struct GoalWidgetView: View {
  let entry: SurfaceEntry
  let family: WidgetFamily

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spaceXs) {
      Text("Goal").textStyle(.label).foregroundStyle(Theme.muted)
      ForEach(Array(entry.today.goalLines.enumerated()), id: \.offset) { _, line in
        Text(line)
          .textStyle(family == .systemSmall ? .subtitle : .headline)
          .lineLimit(2)
          .accessibilityIdentifier("widget.goal.line")
      }
      Spacer(minLength: 0)
      SavedNoteView(note: entry.savedNote)
    }
    .foregroundStyle(Theme.ink)
    .frame(maxWidth: .infinity, alignment: .leading)
    .containerBackground(Theme.surface, for: .widget)
  }
}

/// The Tasks widget (S-062): one line per open task, a red "Overdue" tag on the late ones, and
/// "+N more" when they don't all fit. Read-only: nothing is checked off here.
struct TasksWidgetView: View {
  let entry: SurfaceEntry
  let family: WidgetFamily

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spaceXs) {
      Text("Tasks").textStyle(.label).foregroundStyle(Theme.muted)
      if let list = entry.today.taskList(fitting: lines, now: entry.date, calendar: .current) {
        ForEach(Array(list.rows.enumerated()), id: \.offset) { _, row in
          TaskRowView(row: row)
        }
        if list.more > 0 {
          Text("+\(list.more) more").textStyle(.subtitle).foregroundStyle(Theme.muted)
            .accessibilityIdentifier("widget.tasks.more")
        }
        if list.rows.isEmpty {
          Text("Nothing due today").textStyle(.subtitle)
            .accessibilityIdentifier("widget.tasks.empty")
        }
      } else {
        Text("--").textStyle(.headline).accessibilityIdentifier("widget.tasks.missing")
      }
      Spacer(minLength: 0)
      SavedNoteView(note: entry.savedNote)
    }
    .foregroundStyle(Theme.ink)
    .frame(maxWidth: .infinity, alignment: .leading)
    .containerBackground(Theme.surface, for: .widget)
  }

  /// The lines under the title: 4 in medium and 12 in large, one fewer above a Saved line.
  private var lines: Int { (family == .systemLarge ? 12 : 4) - (entry.savedNote == nil ? 0 : 1) }
}

/// A task on one line, cut with an ellipsis, with its Overdue tag kept whole.
struct TaskRowView: View {
  let row: TaskRow

  var body: some View {
    HStack(spacing: Theme.spaceSm) {
      Text(row.text).textStyle(.subtitle).lineLimit(1)
        .accessibilityIdentifier("widget.tasks.row")
      Spacer(minLength: 0)
      if row.overdue {
        Text("Overdue").textStyle(.label).foregroundStyle(Theme.signalError)
          .layoutPriority(1)
          .accessibilityIdentifier("widget.tasks.overdue")
      }
    }
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
