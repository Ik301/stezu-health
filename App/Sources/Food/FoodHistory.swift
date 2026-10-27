import StezuCore
import SwiftUI
import UIKit

/// Food history (S-019): days newest first with their totals as ranges, pending photos pinned at
/// the top of their day, and each logged meal with its photo, items, ranges and source. A tap on
/// a meal opens the item editor; Save replaces the meal and its Health entry, Delete removes both.
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
        HStack {
          Text("History").textStyle(.subtitle, weight: .semibold)
            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("food.history.title")
          Spacer()
          Button("Done") { dismiss() }.accessibilityIdentifier("food.history.done")
        }
        if days?.isEmpty == true { Text("--").accessibilityIdentifier("food.history.empty") }
        ForEach(Array((days ?? []).enumerated()), id: \.element.day) { index, day in
          dayView(day, id: "food.history.day.\(index)")
        }
      }
      .padding(Theme.spaceLg)
    }
    .scrollIndicators(.hidden)
    .foregroundStyle(Theme.ink).background(Theme.ground)
    .task { await load() }
    .sheet(item: $editing) { meal in
      MealEditor(match: PhotoMatch(mealId: "\(meal.id)", items: meal.items), action: "Save") {
        let edited = LoggedMeal(id: meal.id, loggedAt: meal.loggedAt, items: $0)
        Task { await change(edited, delete: false) }
      }
    }
  }

  private func dayView(_ day: FoodDay, id: String) -> some View {
    VStack(alignment: .leading, spacing: Theme.spaceSm) {
      Text(day.day.formatted(.dateTime.weekday(.wide).month().day()))
        .textStyle(.headline).accessibilityIdentifier(id)
      HStack(spacing: Theme.spaceMd) {
        Text(PhotoMatchSheet.range(day.kcal, unit: "kcal")).accessibilityIdentifier("\(id).kcal")
        Text(PhotoMatchSheet.range(day.proteinG, unit: "g protein"))
          .accessibilityIdentifier("\(id).protein")
      }
      ForEach(Array(day.pending.enumerated()), id: \.element.id) { index, photo in
        row(photo.id, id: "\(id).pending.\(index)", "Pending, will match when online")
      }
      ForEach(Array(day.meals.enumerated()), id: \.element.id) { index, meal in
        HStack {
          row(
            meal.id, id: "\(id).meal.\(index)", meal.items.map(\.name).joined(separator: ", "),
            Self.detail(meal)
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
      PhotoMatchSheet.range(totals.kcal, unit: "kcal") + ", "
        + PhotoMatchSheet.range(totals.proteinG, unit: "g protein"),
      ([meal.loggedAt.formatted(date: .omitted, time: .shortened)] + sources + health)
        .joined(separator: ", "),
    ]
  }

  /// A thumbnail, a title, the ranges and the source; a pending photo has neither yet.
  private func row(
    _ photoID: UUID, id: String, _ title: String,
    _ lines: [String] = ["-- kcal, -- g protein", "Photo saved on this phone"]
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
        Text(lines[0]).accessibilityIdentifier("\(id).ranges")
        Text(lines[1]).foregroundStyle(Theme.muted).accessibilityIdentifier("\(id).source")
      }
      .textStyle(.label).multilineTextAlignment(.leading)
      Spacer(minLength: 0)
    }
    .padding(Theme.spaceSm)
    .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.surface))
  }

  private func load() async {
    let loaded = await environment.mealCaptures.days()
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
