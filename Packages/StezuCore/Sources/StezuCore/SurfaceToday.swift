import Foundation

/// GET /surface/today (server/README.md): the vault's word of the day, its definition, the
/// current goals and the due tasks, each null when the vault has none. The home-screen widgets
/// draw a missing field as "--" and never make one up (S-060, S-061, S-062).
public struct SurfaceToday: Codable, Sendable, Equatable {
  public static let path = "/surface/today"

  /// The server's day, "2026-03-11".
  public var date: String?
  public var word: String?
  public var definition: String?
  /// Up to three goal lines.
  public var goal: [String]?
  /// Open tasks due today or earlier, oldest first; nil when the server couldn't read the notes.
  public var tasks: [SurfaceTask]?

  public init(
    date: String? = nil, word: String? = nil, definition: String? = nil, goal: [String]? = nil,
    tasks: [SurfaceTask]? = nil
  ) {
    self.date = date
    self.word = word
    self.definition = definition
    self.goal = goal
    self.tasks = tasks
  }

  public var wordText: String { Self.shown(word) }
  public var definitionText: String { Self.shown(definition) }
  /// The non-blank goals, at most three, or one "--".
  public var goalLines: [String] {
    let lines = (goal ?? []).map(Self.shown).filter { $0 != "--" }
    return lines.isEmpty ? ["--"] : Array(lines.prefix(3))
  }

  /// "Saved 2026-03-11" when this copy came from the cache and is from an earlier day than `now`,
  /// so yesterday's word never passes as today's. nil for a live reply or today's copy.
  public func savedNote(isCached: Bool, now: Date, calendar: Calendar) -> String? {
    guard isCached, let date, date != Self.day(of: now, calendar: calendar) else { return nil }
    return "Saved \(date)"
  }

  /// The Tasks widget's lines (S-062): every task when they fit in `lines`, else `lines - 1` of
  /// them and a count of the rest. nil when the tasks are missing ("--"), no rows when nothing is
  /// due. Overdue means due before today on the phone, so a list saved yesterday marks
  /// yesterday's tasks overdue this morning.
  public func taskList(fitting lines: Int, now: Date, calendar: Calendar) -> TaskList? {
    guard let tasks else { return nil }
    let today = Self.day(of: now, calendar: calendar)
    let shown = tasks.count <= lines ? tasks : Array(tasks.prefix(max(lines - 1, 0)))
    let rows = shown.map { TaskRow(text: Self.shown($0.text), overdue: ($0.due ?? today) < today) }
    return TaskList(rows: rows, more: tasks.count - shown.count)
  }

  /// The local day of `now`, "2026-03-11", the form the server uses.
  public static func day(of now: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: now)
    return String(
      format: "%04ld-%02ld-%02ld", components.year ?? 0, components.month ?? 0, components.day ?? 0)
  }

  /// When a widget reloads: 5 minutes after the coming local midnight once a fetch worked, since
  /// the server picks the word by date; 30 minutes after a failed one, but never later than that
  /// midnight reload. At most 48 retries a day stays inside WidgetKit's reload budget.
  public static func nextReload(after now: Date, fetched: Bool, calendar: Calendar) -> Date {
    let reload = afterMidnight(now, calendar)
    return fetched ? reload : min(now.addingTimeInterval(30 * 60), reload)
  }

  /// The Tasks widget reloads every 45 minutes, fetched or not, and at the midnight reload when
  /// that comes first: at most 33 reloads a day, under the low end of WidgetKit's budget (S-062).
  public static func nextTasksReload(after now: Date, calendar: Calendar) -> Date {
    min(now.addingTimeInterval(45 * 60), afterMidnight(now, calendar))
  }

  private static func afterMidnight(_ now: Date, _ calendar: Calendar) -> Date {
    let midnight =
      calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
      ?? now.addingTimeInterval(24 * 3600)
    return midnight.addingTimeInterval(5 * 60)
  }

  static func shown(_ text: String?) -> String {
    let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? "--" : trimmed
  }
}

/// One open task from GET /surface/today: its text, its due day ("2026-03-10") and its note.
public struct SurfaceTask: Codable, Sendable, Equatable {
  public var text: String?
  public var due: String?
  public var source: String?

  public init(text: String? = nil, due: String? = nil, source: String? = nil) {
    self.text = text
    self.due = due
    self.source = source
  }
}

/// What the Tasks widget draws: its task lines and how many tasks didn't fit.
public struct TaskList: Sendable, Equatable {
  public var rows: [TaskRow]
  public var more: Int

  public init(rows: [TaskRow], more: Int) {
    self.rows = rows
    self.more = more
  }
}

public struct TaskRow: Sendable, Equatable {
  public var text: String
  public var overdue: Bool

  public init(text: String, overdue: Bool) {
    self.text = text
    self.overdue = overdue
  }
}
