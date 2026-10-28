import Foundation

/// A saved meal photo and, once POST /scan has answered, its match. Without a match it is pending.
public struct QueuedMeal: Sendable, Equatable, Identifiable {
  public let id: UUID
  public let capturedAt: Date
  public var match: PhotoMatch?

  public init(id: UUID, capturedAt: Date, match: PhotoMatch? = nil) {
    self.id = id
    self.capturedAt = capturedAt
    self.match = match
  }

  public var isPending: Bool { match == nil }
}

/// Meal photos in capture order (S-017). Pending meals are retried oldest first; nothing in the
/// queue is ever removed here, matched or not.
public struct MealQueue: Sendable, Equatable {
  public private(set) var meals: [QueuedMeal]

  public init(_ meals: [QueuedMeal] = []) {
    self.meals = meals.sorted { $0.capturedAt < $1.capturedAt }
  }

  public var pending: [QueuedMeal] { meals.filter(\.isPending) }

  public mutating func add(_ meal: QueuedMeal) {
    meals.append(meal)
    meals.sort { $0.capturedAt < $1.capturedAt }
  }

  /// Sends each pending meal to `scan`, oldest first, and returns the ids matched this round.
  /// A transport error (offline, no server set) ends the round and leaves the rest pending; any
  /// other failure leaves that meal pending and moves on to the next.
  public mutating func retry(
    _ scan: (QueuedMeal) async throws -> PhotoMatch
  ) async -> [UUID] {
    var matched: [UUID] = []
    for index in meals.indices where meals[index].isPending {
      do {
        meals[index].match = try await scan(meals[index])
        matched.append(meals[index].id)
      } catch is VMTransportError {
        break
      } catch {
        continue
      }
    }
    return matched
  }

  /// Pending meals captured on the same day as `day`.
  public func pendingCount(on day: Date, calendar: Calendar = .current) -> Int {
    pending.filter { calendar.isDate($0.capturedAt, inSameDayAs: day) }.count
  }

  /// "-- kcal, +1 pending": logged kcal as a range or "--", never 0 for a meal not yet matched.
  public static func todayText(loggedKcal: FoodRange?, pending: Int) -> String {
    let kcal = FoodRange.text(loggedKcal)
    return pending > 0 ? "\(kcal) kcal, +\(pending) pending" : "\(kcal) kcal"
  }
}
