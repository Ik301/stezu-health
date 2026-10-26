import Foundation

/// One day of food (S-019) from its start: logged meals and photos still pending (counted in no
/// total), each newest first, with the day's kcal and protein as summed ranges. Tracking only:
/// no target, no remaining (D-032).
public struct FoodDay: Sendable, Equatable {
  public let day: Date
  public let meals: [LoggedMeal]
  public let pending: [QueuedMeal]

  public init(day: Date, meals: [LoggedMeal], pending: [QueuedMeal] = []) {
    self.day = day
    self.meals = meals.sorted { $0.loggedAt > $1.loggedAt }
    self.pending = pending.sorted { $0.capturedAt > $1.capturedAt }
  }

  /// Every item's low summed and every high summed. Nil with no meal, or when an item has no
  /// range, because an unknown item makes the day's total unknown (absent is not zero).
  public var kcal: FoodRange? { FoodRange.total(meals.flatMap(\.items).map(\.kcal)) }
  public var proteinG: FoodRange? { FoodRange.total(meals.flatMap(\.items).map(\.proteinG)) }

  /// Logged meals; nil with none, so the screen shows "--", not 0.
  public var mealCount: Int? { meals.isEmpty ? nil : meals.count }

  /// How far the totals can be trusted: rough items and pending photos lower it.
  public var confidence: Confidence {
    let rough = meals.flatMap(\.items).filter(\.isRough).count
    let reason = "\(meals.count) logged, \(rough) rough, \(pending.count) pending"
    guard kcal != nil else { return Confidence(level: .low, reason: reason) }
    return Confidence(level: rough + pending.count > 0 ? .medium : .high, reason: reason)
  }

  /// The day holding `date`, from every logged meal and pending photo.
  public static func on(
    _ date: Date, meals: [LoggedMeal], pending: [QueuedMeal] = [], calendar: Calendar = .current
  ) -> FoodDay {
    FoodDay(
      day: calendar.startOfDay(for: date),
      meals: meals.filter { calendar.isDate($0.loggedAt, inSameDayAs: date) },
      pending: pending.filter { calendar.isDate($0.capturedAt, inSameDayAs: date) })
  }

  /// Every day with a meal or a pending photo, newest first.
  public static func days(
    meals: [LoggedMeal], pending: [QueuedMeal] = [], calendar: Calendar = .current
  ) -> [FoodDay] {
    let starts = Set(
      meals.map { calendar.startOfDay(for: $0.loggedAt) }
        + pending.map { calendar.startOfDay(for: $0.capturedAt) })
    return starts.sorted(by: >).map { on($0, meals: meals, pending: pending, calendar: calendar) }
  }
}
