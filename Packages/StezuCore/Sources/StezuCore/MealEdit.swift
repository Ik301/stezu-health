import Foundation

extension MatchedItem {
  /// The same item at `count` servings, its ranges scaled from the servings it came with. An item
  /// that came without a servings count is taken as 1 serving of what was seen.
  public func withServings(_ count: Double) -> MatchedItem {
    let scale = count / (servings ?? 1)
    func scaled(_ range: FoodRange?) -> FoodRange? {
      range.map { FoodRange(low: $0.low * scale, high: $0.high * scale) }
    }
    return MatchedItem(
      itemId: itemId, name: name, hall: hall, halls: halls, brand: brand, serving: serving,
      servings: count, confidence: confidence, rough: rough, kcal: scaled(kcal),
      proteinG: scaled(proteinG))
  }
}

/// The item list before Log (S-015): replace, step servings in halves, remove and add. Totals are
/// summed from the items each time (D-049), so every edit moves them.
public struct MealEdit: Sendable, Equatable {
  public static let step = 0.5
  public private(set) var items: [MatchedItem]

  public init(_ match: PhotoMatch) {
    items = match.items
  }

  public var totalKcal: FoodRange? { FoodRange.total(items.map(\.kcal)) }
  public var totalProteinG: FoodRange? { FoodRange.total(items.map(\.proteinG)) }

  /// One half serving up or down, never below one half; the ranges follow.
  public mutating func step(_ index: Int, up: Bool) {
    guard items.indices.contains(index) else { return }
    let count = (items[index].servings ?? 1) + (up ? Self.step : -Self.step)
    items[index] = items[index].withServings(max(Self.step, count))
  }

  /// The pick takes the place of the item and keeps the servings counted for it.
  public mutating func replace(_ index: Int, with item: MatchedItem) {
    guard items.indices.contains(index) else { return }
    items[index] = item.withServings(items[index].servings ?? 1)
  }

  public mutating func remove(_ index: Int) {
    guard items.indices.contains(index) else { return }
    items.remove(at: index)
  }

  /// A new item joins the end of the list at 1 serving.
  public mutating func add(_ item: MatchedItem) {
    items.append(item.withServings(1))
  }
}

/// A meal after the Log tap: the items as confirmed, kept on the phone.
public struct LoggedMeal: Sendable, Equatable, Codable, Identifiable {
  public enum Status: String, Sendable, Codable { case confirmed }
  public let id: UUID
  public let loggedAt: Date
  public let status: Status
  public let items: [MatchedItem]

  public init(id: UUID, loggedAt: Date, items: [MatchedItem]) {
    self.id = id
    self.loggedAt = loggedAt
    self.status = .confirmed
    self.items = items
  }
}
