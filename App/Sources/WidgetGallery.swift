import StezuCore
import SwiftUI

/// `-uitest-widgets` only: the home-screen widgets drawn at their small and medium sizes, loaded
/// through the same fetch and cache as the extension but from the fake server, so UI tests can
/// check and screenshot them (S-060, S-061). A `surface-tasks` scenario shows the Tasks widget at
/// medium and large size instead (S-062). The live app never shows it.
struct WidgetGallery: View {
  /// Kept across launches, so an offline relaunch finds the last good copy. `-uitest-reset`
  /// empties it.
  nonisolated static let cacheFolder = FileManager.default.temporaryDirectory
    .appendingPathComponent("stezu-uitest-widget-cache", isDirectory: true)

  @Environment(\.appEnvironment) private var environment
  @State private var entry: SurfaceEntry?

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spaceLg) {
      if let entry, environment.scenario?.hasPrefix("surface-tasks") == true {
        tile(TasksWidgetView(entry: entry, family: .systemMedium), width: 338)
        tile(TasksWidgetView(entry: entry, family: .systemLarge), width: 338, height: 354)
      } else if let entry {
        HStack(spacing: Theme.spaceLg) {
          tile(WordWidgetView(entry: entry, family: .systemSmall), width: 158)
          tile(GoalWidgetView(entry: entry, family: .systemSmall), width: 158)
        }
        tile(WordWidgetView(entry: entry, family: .systemMedium), width: 338)
        tile(GoalWidgetView(entry: entry, family: .systemMedium), width: 338)
      }
      Spacer()
    }
    .padding(Theme.spaceLg)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Theme.ground)
    .task {
      let cache = PayloadCache(directory: Self.cacheFolder)
      let fetcher = CachedPayloadFetcher(transport: environment.vmTransport, cache: cache)
      entry = await SurfaceEntry.load(with: fetcher).entry
    }
  }

  /// A widget's frame on a 6.1-inch iPhone, with the margins the home screen adds.
  private func tile(_ widget: some View, width: CGFloat, height: CGFloat = 158) -> some View {
    widget
      .padding(Theme.spaceLg)
      .frame(width: width, height: height)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
  }
}
