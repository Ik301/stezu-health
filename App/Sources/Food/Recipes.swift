import StezuCore
import SwiftUI

/// S-059 (D-149): the camera's Recipes sheet. Each saved recipe with its totals and item count;
/// a tap opens its items as a meal, ready to Log; swipe left for Edit and Delete (then Confirm).
/// Recipes stay on the phone: only a meal logged from one reaches Health and Hermes.
struct RecipesSheet: View {
  /// The Log tap on a recipe's meal; FoodView logs it like any meal and closes this sheet.
  let log: ([MatchedItem]) -> Void
  @Environment(\.appEnvironment) private var environment
  @Environment(\.dismiss) private var dismiss
  @State private var recipes: [Recipe] = []
  @State private var editing: Editing?
  @State private var logging: Recipe?
  @State private var swiped: UUID?
  @State private var confirming: UUID?

  /// The recipe editor's sheet: nil for a new recipe.
  struct Editing: Identifiable {
    let id = UUID()
    let recipe: Recipe?
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.spaceSm) {
        TopBar(
          title: "Recipes", titleID: "food.recipes.list",
          action: .init(title: "Done", id: "food.recipes.done") { dismiss() })
        Button("+ New recipe") { editing = Editing(recipe: nil) }
          .textStyle(.headline).foregroundStyle(Theme.ink)
          .frame(maxWidth: .infinity, minHeight: Theme.sizeTarget)
          .background(Capsule().fill(Theme.surfaceRaised))
          .accessibilityIdentifier("food.recipes.new")
          .sheet(item: $editing) { editing in
            MealEditor(recipe: editing.recipe) { saveEdit(editing.recipe, $0, $1) }
          }
        if recipes.isEmpty {
          Text("No recipes yet").textStyle(.subtitle).foregroundStyle(Theme.muted)
            .accessibilityIdentifier("food.recipes.empty")
        }
        ForEach(Array(recipes.enumerated()), id: \.element.id) { index, recipe in
          row(recipe, id: "food.recipes.row.\(index)")
        }
      }
      .padding(Theme.spaceLg)
      .sheet(item: $logging) { recipe in MealEditor(match: recipe.meal(id: UUID()), log: log) }
    }
    .scrollIndicators(.hidden)
    .foregroundStyle(Theme.ink).background(Theme.ground)
    .presentationDragIndicator(.visible)
    .task { recipes = await environment.recipes.recipes }
  }

  /// Name, "240–340 kcal", "20–30 g protein" and "2 items"; Edit and Delete after a swipe left.
  private func row(_ recipe: Recipe, id: String) -> some View {
    HStack(spacing: Theme.spaceSm) {
      VStack(alignment: .leading, spacing: Theme.spaceXs) {
        Text(recipe.name).textStyle(.headline).accessibilityIdentifier("\(id).name")
        HStack(spacing: Theme.spaceSm) {
          RangeLabel(range: recipe.totalKcal, unit: "kcal", style: .label)
            .accessibilityIdentifier("\(id).kcal")
          RangeLabel(
            range: recipe.totalProteinG, unit: "g", spoken: "g protein", color: Theme.dataProtein,
            style: .label
          )
          .accessibilityIdentifier("\(id).protein")
        }
        Text("\(recipe.items.count) item\(recipe.items.count == 1 ? "" : "s")").textStyle(.label)
          .foregroundStyle(Theme.muted).accessibilityIdentifier("\(id).count")
      }
      Spacer(minLength: 0)
      if swiped == recipe.id {
        action("Edit", id: "\(id).edit") { (swiped, editing) = (nil, Editing(recipe: recipe)) }
        action(confirming == recipe.id ? "Confirm" : "Delete", id: "\(id).delete") {
          if confirming == recipe.id { save(recipe, delete: true) } else { confirming = recipe.id }
        }
      }
    }
    .padding(Theme.spaceMd)
    .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.surface))
    .contentShape(Rectangle())
    .onTapGesture {
      if swiped == nil { logging = recipe } else { (swiped, confirming) = (nil, nil) }
    }
    .simultaneousGesture(
      DragGesture(minimumDistance: Theme.spaceXl).onEnded { drag in
        let (dx, dy) = (drag.translation.width, drag.translation.height)
        if dx < -Theme.sizeTarget, abs(dx) > abs(dy) { withAnimation { swiped = recipe.id } }
      }
    )
    .accessibilityElement(children: .contain).accessibilityIdentifier(id)
  }

  private func action(_ title: String, id: String, run: @escaping () -> Void) -> some View {
    Button(title, action: run).textStyle(.label, weight: .medium)
      .foregroundStyle(Theme.ink).padding(.horizontal, Theme.spaceMd).frame(minHeight: 32)
      .background(Theme.surfaceRaised, in: Capsule()).accessibilityIdentifier(id)
  }

  /// Saves a new or edited recipe in recipes.json, or deletes one; meals logged from it stay.
  private func saveEdit(_ old: Recipe?, _ name: String, _ items: [MatchedItem]) {
    let name = Recipe.name(name) ?? name
    save(Recipe(id: old?.id ?? UUID(), name: name, items: items, at: environment.now()))
  }

  private func save(_ recipe: Recipe, delete: Bool = false) {
    (editing, swiped, confirming) = (nil, nil, nil)
    Task { recipes = await environment.recipes.set(recipe, delete: delete, at: environment.now()) }
  }
}

/// The camera's Barcode mode inside the recipe editor (S-016): VisionKit on the phone, the
/// fixture code a second after opening in `-uitest`; GET /barcode, and "Not found" offers search.
struct RecipeBarcode: View {
  /// Cancel and a found product close the scanner; "Search instead" opens search.
  @Binding var target: MealEditor.SearchTarget?
  let found: (MatchedItem) -> Void
  @Environment(\.appEnvironment) private var environment
  @State private var state = BarcodeState.scanning

  var body: some View {
    VStack(spacing: Theme.spaceSm) {
      TopBar(
        title: "Barcode", titleID: "food.recipe.scan",
        action: .init(title: "Cancel", id: "food.edit.search.cancel", run: { target = nil }))
      ZStack {
        if case .camera = environment.barcodeSource, BarcodeScannerView.available {
          BarcodeScannerView { code in Task { await lookUp(code) } }
        }
        BarcodeStatusView(state: state) { target = .add }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Theme.camera).clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard))
    }
    .padding(Theme.spaceLg)
    .task {
      (environment.photoSource as? LiveCameraPhotoSource)?.stop()
      guard case .fixture(let code) = environment.barcodeSource,
        (try? await Task.sleep(nanoseconds: 1_000_000_000)) != nil
      else { return }
      await lookUp(code)
    }
    .onDisappear { (environment.photoSource as? LiveCameraPhotoSource)?.start() }
  }

  private func lookUp(_ code: String) async {
    guard state == .scanning, BarcodeClient.isGTIN(code) else { return }
    state = .lookingUp
    do {
      switch try await BarcodeClient(transport: environment.vmTransport).lookup(code) {
      case .found(let item):
        found(item)
        target = nil
      case .notFound: state = .notFound
      }
    } catch {
      state = .failed
    }
  }
}

extension AppEnvironment {
  /// recipes.json in Application Support, beside the meals folder; memory only in `-uitest`.
  static func recipesFile(storage: StorageMode) -> RecipeStore {
    let file = FinishedWorkoutStore(storage: storage).file?.deletingLastPathComponent()
      .appendingPathComponent("recipes.json")
    let saved = file.flatMap {
      try? JSONDecoder().decode([Recipe].self, from: Data(contentsOf: $0))
    }
    return RecipeStore(saved ?? []) { recipes in
      guard let file, let data = try? JSONEncoder().encode(recipes) else { return }
      try? data.write(to: file, options: .atomic)
    }
  }
}
