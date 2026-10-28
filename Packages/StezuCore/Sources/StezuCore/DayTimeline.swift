import Foundation

/// The Day view's timeline (S-041) in points from midnight: an hour with a mark in it is full
/// height, an empty hour folds to a thin band. Visits sit in their own column and open no hours.
public struct DayTimeline: Sendable {
  /// A mark's place: its lane among the marks it overlaps, of `lanes`.
  public typealias Placed = (top: Double, height: Double, lane: Int, lanes: Int)

  public static let (fullHour, foldedHour) = (40.0, 10.0)
  /// A mark is a tap target tall at least; a point (a weigh-in) keeps an hour open after it.
  public static let shortest = 44.0
  public let start: Date
  public let hours: [Double]
  public let marks: [Placed?]  // one per span; nil for a span wholly outside the day
  public var height: Double { hours.reduce(0, +) }

  public init(day: Date, spans: [DateInterval], calendar: Calendar = .current) {
    let start = calendar.startOfDay(for: day)
    let minutes = spans.map { span -> (Double, Double)? in
      let (a, b) = (
        span.start.timeIntervalSince(start) / 60, span.end.timeIntervalSince(start) / 60
      )
      return a < 1440 && (b > 0 || a == 0) ? (max(a, 0), min(b, 1440)) : nil
    }
    let hours = (0..<24).map { h in
      let busy = minutes.contains {
        $0.map { $0.0 < Double(h + 1) * 60 && max($0.1, $0.0 + 60) > Double(h) * 60 } ?? false
      }
      return busy ? Self.fullHour : Self.foldedHour
    }
    let y = { Self.y($0, hours) }
    var marks = [Placed?](repeating: nil, count: spans.count)
    var (cluster, ends): ([(Int, Double, Double, Int)], [Double]) = ([], [])
    func close() {
      for (i, top, bottom, lane) in cluster {
        marks[i] = (top, bottom - top, lane, ends.count)
      }
      (cluster, ends) = ([], [])
    }
    for index in spans.indices.sorted(by: { (minutes[$0]?.0 ?? 0) < (minutes[$1]?.0 ?? 0) }) {
      guard let span = minutes[index] else { continue }
      let top = min(y(span.0), y(1440) - Self.shortest)  // a late mark ends at 24:00
      let bottom = max(y(span.1), top + Self.shortest)
      if ends.allSatisfy({ $0 <= top }) { close() }  // nothing open overlaps: a new cluster
      let lane = ends.firstIndex { $0 <= top } ?? ends.count
      if lane == ends.count { ends.append(bottom) } else { ends[lane] = bottom }
      cluster.append((index, top, bottom, lane))
    }
    close()
    (self.start, self.hours, self.marks) = (start, hours, marks)
  }

  public func y(_ date: Date) -> Double { Self.y(date.timeIntervalSince(start) / 60, hours) }

  static func y(_ minutes: Double, _ hours: [Double]) -> Double {
    let clamped = min(max(minutes, 0), 1440)
    let hour = min(23, Int(clamped / 60))
    return hours[..<hour].reduce(0, +) + (clamped - Double(hour) * 60) / 60 * hours[hour]
  }
}
