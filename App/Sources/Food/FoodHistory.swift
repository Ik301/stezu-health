import StezuCore
import SwiftUI
import UIKit

/// Food Today (S-043), from History: today's ranges large in their data colours, today's meals,
/// this week as one low-to-high band per day, then past days (S-019) newest first. Pending photos
/// sit at the top of their day; each meal has its photo, items, ranges and source. A tap on a
/// meal opens the item editor; Save replaces the meal and its Health entry, Delete removes both.
struct FoodHistory: View {
  /// Called after every save or delete, so the camera's strip follows.
  var changed: () -> Void = {}
  @Environment(\.appEnvironment) private var environment
  @Environment(\.dismiss) private var dismiss
  @State private var days: [FoodDay]?
  @State private var photos: [UUID: UIImage] = [:]
  @State private var editing: LoggedMeal?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.spaceMd) {
        TopBar(
          title: "Today", titleID: "food.history.title",
          action: .init(title: "Done", id: "food.history.done") { dismiss() })
        Text(environment.now().formatted(.dateTime.weekday().day().month()))
          .textStyle(.label).foregroundStyle(Theme.muted)
        if let days {
          ForEach(Array(days.enumerated()), id: \.element.day) { index, day in
            if index == 0 {
              todayView(day, id: "food.history.day.0")
              FoodWeekBands(days: week(days), id: "food.today.week")
                .padding(Theme.spaceCard).background(card)
              if days.count > 1 {
                Text("Past days").textStyle(.headline).padding(.top, Theme.spaceSm)
              }
            } else {
              dayView(day, id: "food.history.day.\(index)")
            }
          }
        }
      }
      .padding(Theme.spaceLg)
    }
    .scrollIndicators(.hidden)
    .foregroundStyle(Theme.ink).background(Theme.ground)
    .presentationDragIndicator(.visible)
    .task { await load() }
    .sheet(item: $editing) { meal in
      MealEditor(match: PhotoMatch(mealId: "\(meal.id)", items: meal.items), action: "Save") {
        let edited = LoggedMeal(id: meal.id, loggedAt: meal.loggedAt, items: $0)
        Task { await change(edited, delete: false) }
      }
    }
  }

  private var card: some View {
    RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.surface)
  }

  /// Today first: the ranges large in their data colours, then its pending photos and meals.
  private func todayView(_ day: FoodDay, id: String) -> some View {
    VStack(alignment: .leading, spacing: Theme.spaceMd) {
      VStack(alignment: .leading, spacing: Theme.spaceSm) {
        HStack(alignment: .top, spacing: Theme.spaceXl) {
          PhotoMatchSheet.total(
            "Energy", day.kcal, unit: "kcal", spoken: "kcal", color: Theme.dataEnergy,
            id: "\(id).kcal")
          PhotoMatchSheet.total(
            "Protein", day.proteinG, unit: "g", spoken: "g protein", color: Theme.dataProtein,
            id: "\(id).protein")
        }
        Text(
          day.mealCount.map {
            "\($0) meal\($0 == 1 ? "" : "s") logged. Ranges add the lows and the highs."
          }
            ?? "No meals logged yet."
        )
        .textStyle(.label).foregroundStyle(Theme.muted)
      }
      .padding(Theme.spaceCard).frame(maxWidth: .infinity, alignment: .leading).background(card)
      meals(day, id: id)
    }
  }

  private func dayView(_ day: FoodDay, id: String) -> some View {
    VStack(alignment: .leading, spacing: Theme.spaceSm) {
      Text(day.day.formatted(.dateTime.weekday(.wide).month().day()))
        .textStyle(.headline).accessibilityIdentifier(id)
      HStack(spacing: Theme.spaceMd) {
        Text(FoodRange.text(day.kcal, unit: "kcal")).accessibilityIdentifier("\(id).kcal")
        Text(FoodRange.text(day.proteinG, unit: "g protein"))
          .accessibilityIdentifier("\(id).protein")
      }
      meals(day, id: id)
    }
    .textStyle(.subtitle)
  }

  /// A day's pending photos, then its meals, each with Delete beside it.
  private func meals(_ day: FoodDay, id: String) -> some View {
    VStack(alignment: .leading, spacing: Theme.spaceSm) {
      ForEach(Array(day.pending.enumerated()), id: \.element.id) { index, photo in
        row(photo.id, id: "\(id).pending.\(index)", "Pending, will match when online")
      }
      ForEach(Array(day.meals.enumerated()), id: \.element.id) { index, meal in
        HStack {
          let totals = FoodEntry(meal: meal)
          row(
            meal.id, id: "\(id).meal.\(index)", meal.items.map(\.name).joined(separator: ", "),
            Self.detail(meal), ranges: (totals.kcal, totals.proteinG)
          )
          .contentShape(Rectangle()).onTapGesture { editing = meal }
          Button("Delete") { Task { await change(meal, delete: true) } }
            .textStyle(.label, weight: .medium).padding(.horizontal, Theme.spaceMd)
            .frame(minHeight: 32).background(Theme.surfaceRaised, in: Capsule())
            .accessibilityIdentifier("\(id).meal.\(index).delete")
        }
      }
    }
    .textStyle(.subtitle)
  }

  /// "240-340 kcal, 6-9 g protein", then "12:30 PM, North Hall, In Health".
  static func detail(_ meal: LoggedMeal) -> [String] {
    let totals = FoodEntry(meal: meal)
    let sources = meal.items.map { $0.hall ?? $0.brand ?? ($0.isRough ? "Estimate" : "--") }
      .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    let health = meal.inHealth.map { $0 ? ["In Health"] : ["Not in Health"] } ?? []
    return [
      FoodRange.text(totals.kcal, unit: "kcal") + ", "
        + FoodRange.text(totals.proteinG, unit: "g protein"),
      ([meal.loggedAt.formatted(date: .omitted, time: .shortened)] + sources + health)
        .joined(separator: ", "),
    ]
  }

  /// A thumbnail, a title, the ranges and the source; a pending photo has neither yet.
  private func row(
    _ photoID: UUID, id: String, _ title: String,
    _ lines: [String] = ["-- kcal, -- g protein", "Photo saved on this phone"],
    ranges: (kcal: FoodRange?, protein: FoodRange?) = (nil, nil)
  ) -> some View {
    HStack(alignment: .top, spacing: Theme.spaceSm) {
      Theme.surfaceRaised.frame(width: 48, height: 48)
        .overlay { photos[photoID].map { Image(uiImage: $0).resizable().scaledToFill() } }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusInner))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(photos[photoID] == nil ? "No photo" : "Photo")
        .accessibilityIdentifier("\(id).photo")
      VStack(alignment: .leading, spacing: Theme.space2xs) {
        Text(title).textStyle(.subtitle, weight: .medium)
          .accessibilityIdentifier("\(id).items")
        HStack(spacing: Theme.spaceSm) {
          RangeLabel(range: ranges.kcal, unit: "kcal", style: .label)
          RangeLabel(range: ranges.protein, unit: "g", color: Theme.dataProtein, style: .label)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(lines[0])
        .accessibilityIdentifier("\(id).ranges")
        Text(lines[1]).foregroundStyle(Theme.muted).accessibilityIdentifier("\(id).source")
      }
      .textStyle(.label).multilineTextAlignment(.leading)
      Spacer(minLength: 0)
    }
    .padding(Theme.spaceSm)
    .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.surface))
  }

  /// The last 7 days, oldest first, each with its kcal range; nil for a day with nothing logged.
  private func week(_ days: [FoodDay]) -> [FoodWeekBands.Day] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: environment.now())
    return (0..<7).reversed().compactMap { back in
      calendar.date(byAdding: .day, value: -back, to: today).map { day in
        FoodWeekBands.Day(
          day: day, kcal: days.first { calendar.isDate($0.day, inSameDayAs: day) }?.kcal)
      }
    }
  }

  /// Every day with food, newest first, with today always first so Food Today has its day.
  private func load() async {
    var loaded = await environment.mealCaptures.days()
    let now = environment.now()
    if !(loaded.first.map { Calendar.current.isDate($0.day, inSameDayAs: now) } ?? false) {
      loaded.insert(FoodDay(day: Calendar.current.startOfDay(for: now), meals: []), at: 0)
    }
    for id in loaded.flatMap({ $0.meals.map(\.id) + $0.pending.map(\.id) }) where photos[id] == nil
    {
      photos[id] = await environment.mealCaptures.photo(for: id).flatMap(UIImage.init(data:))
    }
    days = loaded
  }

  /// Save puts the edit on the phone and replaces its Health entry; Delete removes both.
  private func change(_ meal: LoggedMeal, delete: Bool) async {
    editing = nil
    let (store, health) = (environment.mealCaptures, environment.healthStore)
    if delete {
      _ = await MealHealth.delete(meal.id, health: health) { await store.unlog($0) }
      await environment.syncMeal(nil, id: meal.id)
    } else if let written = try? await MealHealth.replace(
      meal, health: health, save: { try await store.log($0) })
    {
      await environment.syncMeal(written, id: meal.id, edited: true)
    }
    await load()
    changed()
  }
}
