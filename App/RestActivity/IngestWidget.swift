import Foundation
import StezuCore
import SwiftUI
import WidgetKit

/// The home-screen widget shell (D-152). For now it shows "--"; the word, goal and tasks cards
/// replace the probe below with GET /surface/today and draw its fields.
struct IngestWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "IngestWidget", provider: IngestTimelineProvider()) { entry in
      IngestWidgetView(entry: entry)
    }
    .configurationDisplayName("Ingest")
    .description("A placeholder until the word, goal and tasks widgets arrive.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct IngestEntry: TimelineEntry, Sendable {
  let date: Date
  let text: String

  static let empty = IngestEntry(date: .now, text: "--")
}

/// Every reload makes one authenticated request with the app's address and token from the
/// Keychain, so the device check in docs/decisions/widget-auth.md can see it in the server log.
/// The entry stays "--" whatever the answer.
struct IngestTimelineProvider: TimelineProvider {
  /// Any JSON object; the probe only proves the token reached the server.
  struct Probe: Decodable, Sendable {}

  func placeholder(in context: Context) -> IngestEntry { .empty }

  func getSnapshot(in context: Context, completion: @escaping (IngestEntry) -> Void) {
    completion(.empty)
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<IngestEntry>) -> Void) {
    nonisolated(unsafe) let reply = completion
    Task {
      _ = await WidgetServer.fetcher().fetch(Probe.self, path: "/sync/status")
      let next = Date.now.addingTimeInterval(60 * 60)
      reply(Timeline(entries: [IngestEntry(date: .now, text: "--")], policy: .after(next)))
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

struct IngestWidgetView: View {
  let entry: IngestEntry

  var body: some View {
    Text(entry.text)
      .textStyle(.big)
      .foregroundStyle(Theme.ink)
      .accessibilityIdentifier("widget.ingest.value")
      .containerBackground(Theme.surface, for: .widget)
  }
}
