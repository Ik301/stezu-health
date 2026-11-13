import StezuCore
import SwiftUI

/// Results under the camera's search bar (S-014): GET /search as the text changes, grouped.
/// A tap picks an item at 1 serving; "Estimate from text" asks for a rough estimate instead.
struct FoodSearchPanel: View {
  let query: String
  let pick: (MatchedItem) -> Void
  @Environment(\.appEnvironment) private var environment
  @State private var groups: [FoodSearchGroup]?
  @State private var status = "Searching..."

  /// Each listed group's heading; USDA FoodData Central holds the restaurant and generic dishes.
  /// The groups themselves come in the server's order, his own foods first (D-158).
  static let titles: [FoodSearchSource: String] = [
    .history: "Your foods", .dining: "Dining halls", .usdaFdc: "Restaurants and generic (USDA)",
    .openFoodFacts: "Packaged food",
  ]

  /// The groups the list shows, in the order the server ranked them; never re-sorted here.
  static func listed(_ groups: [FoodSearchGroup]) -> [(group: FoodSearchGroup, title: String)] {
    groups.filter(\.isListed).compactMap { group in
      (titles[group.source] ?? group.title).map { (group, $0) }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spaceSm) {
      Button("Estimate from text") { Task { await estimate() } }
        .textStyle(.label, weight: .semibold)
        .foregroundStyle(Theme.onInvert)
        .padding(.horizontal, Theme.spaceMd).padding(.vertical, Theme.spaceSm)
        .background(Capsule().fill(Theme.invert))
        .accessibilityIdentifier("food.search.estimate")
      ScrollView {
        VStack(alignment: .leading, spacing: Theme.spaceSm) {
          Text(status).accessibilityIdentifier("food.search.status")
          ForEach(Self.listed(groups ?? []), id: \.group.source) { section in
            groupView(section.group, title: section.title)
          }
        }
      }
      .scrollIndicators(.hidden)
    }
    .textStyle(.label).foregroundStyle(Theme.muted)
    .padding(Theme.spaceMd)
    .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.ground))
    .task(id: query) { await search() }
  }

  @ViewBuilder private func groupView(_ group: FoodSearchGroup, title: String) -> some View {
    let id = "food.search.group.\(group.source.rawValue)"
    Text(title).textStyle(.label, weight: .semibold)
      .accessibilityAddTraits(.isHeader).accessibilityIdentifier(id)
    if group.status == "error" || group.items.isEmpty {
      Text(group.status == "error" ? "Could not load" : "No matches")
    }
    ForEach(Array(group.results.enumerated()), id: \.offset) { index, result in
      let item = result.item
      let id = "food.search.result.\(group.source.rawValue).\(index)"
      VStack(alignment: .leading, spacing: Theme.space2xs) {
        HStack {
          Text(item.name).textStyle(.subtitle, weight: .medium)
            .foregroundStyle(Theme.ink).accessibilityIdentifier("\(id).name")
          Spacer()
          Text(FoodRange.text(item.kcal, unit: "kcal")).foregroundStyle(Theme.ink)
            .accessibilityIdentifier("\(id).kcal")
        }
        Text(result.detail).accessibilityIdentifier("\(id).detail")
      }
      .padding(Theme.spaceSm)
      .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.surface))
      .contentShape(Rectangle()).onTapGesture { pick(item) }
      .accessibilityElement(children: .contain).accessibilityAddTraits(.isButton)
    }
  }

  private var today: String {
    Date.ISO8601FormatStyle(timeZone: .current).year().month().day().format(environment.now())
  }

  private func search() async {
    do {
      try await Task.sleep(nanoseconds: 300_000_000)
      groups = try await FoodSearchClient(transport: environment.vmTransport)
        .search(query, date: today, meal: MealPeriod.at(environment.now()))
      status = ""
    } catch {
      guard !Task.isCancelled else { return }
      (groups, status) = (nil, "Search failed")
    }
  }

  private func estimate() async {
    let client = FoodSearchClient(transport: environment.vmTransport)
    if let item = try? await client.estimate(query, date: today) {
      pick(item)
    } else {
      status = "Could not estimate"
    }
  }
}
