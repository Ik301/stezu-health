import Foundation

/// GET /surface/today (server/README.md): the vault's word of the day and its definition, each
/// null when the vault has none. The home-screen widgets draw a missing field as "--" and never
/// make one up (S-060).
public struct SurfaceToday: Codable, Sendable, Equatable {
  public static let path = "/surface/today"

  /// The server's day, "2026-03-11".
  public var date: String?
  public var word: String?
  public var definition: String?

  public init(date: String? = nil, word: String? = nil, definition: String? = nil) {
    self.date = date
    self.word = word
    self.definition = definition
  }

  public var wordText: String { Self.shown(word) }
  public var definitionText: String { Self.shown(definition) }

  /// "Saved 2026-03-11" when this copy came from the cache and is from an earlier day than `now`,
  /// so yesterday's word never passes as today's. nil for a live reply or today's copy.
  public func savedNote(isCached: Bool, now: Date, calendar: Calendar) -> String? {
    let components = calendar.dateComponents([.year, .month, .day], from: now)
    let today = String(
      format: "%04ld-%02ld-%02ld", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    guard isCached, let date, date != today else { return nil }
    return "Saved \(date)"
  }

  /// When a widget reloads: 5 minutes after the coming local midnight once a fetch worked, since
  /// the server picks the word by date; 30 minutes after a failed one, but never later than that
  /// midnight reload. At most 48 retries a day stays inside WidgetKit's reload budget.
  public static func nextReload(after now: Date, fetched: Bool, calendar: Calendar) -> Date {
    let midnight =
      calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
      ?? now.addingTimeInterval(24 * 3600)
    let afterMidnight = midnight.addingTimeInterval(5 * 60)
    return fetched ? afterMidnight : min(now.addingTimeInterval(30 * 60), afterMidnight)
  }

  static func shown(_ text: String?) -> String {
    let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? "--" : trimmed
  }
}
