import Foundation
import StezuCore
import SwiftUI
import WidgetKit

/// The Word widget (S-060). It keeps the kind of the placeholder "Ingest" widget (D-152), so the
/// one already on the home screen turns into it.
struct IngestWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "IngestWidget", provider: SurfaceTimelineProvider()) { entry in
      FamilyReader { WordWidgetView(entry: entry, family: $0) }
    }
    .configurationDisplayName("Word")
    .description("Today's word from your vault and its definition.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

/// The Goal widget (S-061): the same payload and reload schedule as the Word widget.
struct GoalWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "IngestGoal", provider: SurfaceTimelineProvider()) { entry in
      FamilyReader { GoalWidgetView(entry: entry, family: $0) }
    }
    .configurationDisplayName("Goal")
    .description("Your current goals from your vault.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

/// The Tasks widget (S-062): the same payload, reloaded every 45 minutes.
struct TasksWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "IngestTasks", provider: SurfaceTimelineProvider(frequent: true)) {
      entry in
      FamilyReader { TasksWidgetView(entry: entry, family: $0) }
    }
    .configurationDisplayName("Tasks")
    .description("Your open tasks due today, and overdue ones, from your vault.")
    .supportedFamilies([.systemMedium, .systemLarge])
  }
}

/// Passes the widget's size to a view, which can't read it outside a widget (the app's gallery).
struct FamilyReader<Content: View>: View {
  @Environment(\.widgetFamily) private var family
  private let content: (WidgetFamily) -> Content

  init(@ViewBuilder content: @escaping (WidgetFamily) -> Content) {
    self.content = content
  }

  var body: some View { content(family) }
}

/// Every reload makes one GET /surface/today with the app's address and token from the Keychain,
/// falls back to the last good copy, and reloads after local midnight or retries (D-154), or
/// every 45 minutes when `frequent` (Tasks).
struct SurfaceTimelineProvider: TimelineProvider {
  var frequent = false

  func placeholder(in context: Context) -> SurfaceEntry { SurfaceEntry(date: .now) }

  func getSnapshot(in context: Context, completion: @escaping (SurfaceEntry) -> Void) {
    nonisolated(unsafe) let reply = completion
    Task { reply(await SurfaceEntry.load(with: WidgetServer.fetcher()).entry) }
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SurfaceEntry>) -> Void) {
    nonisolated(unsafe) let reply = completion
    Task {
      let (entry, next) = await SurfaceEntry.load(with: WidgetServer.fetcher(), frequent: frequent)
      reply(Timeline(entries: [entry], policy: .after(next)))
    }
  }
}

/// What a widget uses to reach the server: the app's settings from the Keychain, and a cache in
/// this extension's own Application Support folder (no App Group).
enum WidgetServer {
  static func fetcher() -> CachedPayloadFetcher {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
    let directory = support[0].appendingPathComponent("widget-cache", isDirectory: true)
    return CachedPayloadFetcher(
      transport: ServerSettings.fromKeychain().transport(),
      cache: PayloadCache(directory: directory))
  }
}
