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

  /// The groups shown, in order; USDA FoodData Central holds the restaurant and generic dishes.
  static let sections: [(source: FoodSearchSource, title: String)] = [
    (.dining, "Dining halls"), (.usdaFdc, "Restaurants and generic (USDA)"),
    (.openFoodFacts, "Packaged food"),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button("Estimate from text") { Task { await estimate() } }
        .font(.system(size: Theme.labelSize, weight: .semibold))
        .foregroundStyle(Theme.invertedText).padding(.horizontal, 14).padding(.vertical, 8)
        .background(Capsule().fill(Theme.invertedCard))
        .accessibilityIdentifier("food.search.estimate")
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          Text(status).accessibilityIdentifier("food.search.status")
          ForEach(Self.sections.indices, id: \.self) { index in
            if let group = groups?.first(where: { $0.source == Self.sections[index].source }),
              group.status != "skipped"
            {
              groupView(group, title: Self.sections[index].title)
            }
          }
        }
      }
    }
    .font(.system(size: Theme.labelSize)).foregroundStyle(Theme.label)
    .padding(12)
    .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.background))
    .task(id: query) { await search() }
  }

  @ViewBuilder private func groupView(_ group: FoodSearchGroup, title: String) -> some View {
    let id = "food.search.group.\(group.source.rawValue)"
    Text(title).font(.system(size: Theme.labelSize, weight: .semibold))
      .accessibilityAddTraits(.isHeader).accessibilityIdentifier(id)
    if group.status == "error" || group.items.isEmpty {
      Text(group.status == "error" ? "Could not load" : "No matches")
    }
    ForEach(Array(group.items.enumerated()), id: \.offset) { index, item in
      let id = "food.search.result.\(group.source.rawValue).\(index)"
      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Text(item.name).font(.system(size: Theme.subtitleSize, weight: .medium))
            .foregroundStyle(Theme.text).accessibilityIdentifier("\(id).name")
          Spacer()
          Text(PhotoMatchSheet.range(item.kcal, unit: "kcal")).foregroundStyle(Theme.text)
            .accessibilityIdentifier("\(id).kcal")
        }
        Text(Self.detail(item)).accessibilityIdentifier("\(id).detail")
      }
      .padding(10)
      .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.card))
      .contentShape(Rectangle()).onTapGesture { pick(item) }
      .accessibilityElement(children: .contain).accessibilityAddTraits(.isButton)
    }
  }

  /// "North Hall, South Hall · 4 oz" or "Example Brand · 1 cup"; "--" with neither.
  static func detail(_ item: MatchedItem) -> String {
    let place = item.halls.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") } ?? item.brand
    let parts = [place, item.serving].compactMap { $0 }
    return parts.isEmpty ? "--" : parts.joined(separator: " · ")
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
