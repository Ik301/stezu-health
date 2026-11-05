import StezuCore
import SwiftUI

/// The item list after a photo or a pick (S-015): tap a name to replace it, - and + in half
/// servings beside it, swipe left to remove, + Add item, and the single Log button. Totals
/// follow every edit (D-049). S-059: the same list edits a recipe, with a name and Barcode.
struct MealEditor: View {
  let log: ([MatchedItem]) -> Void
  /// The button's title: "Log" after a photo or pick, "Save" for a meal from history (S-019).
  let action: String
  /// Set for a recipe: Save hands over the name and the ingredients.
  private var saveRecipe: ((String, [MatchedItem]) -> Void)?
  @State private var name = ""
  @State private var edit: MealEdit
  @State private var searching: SearchTarget?
  @State private var query = ""
  @State private var detent = PresentationDetent.medium
  @FocusState private var focused: Bool
  @Environment(\.dismiss) private var dismiss

  /// What a search pick does: take an item's place, or join the list.
  enum SearchTarget: Equatable {
    case replace(Int)
    case add
    case barcode
  }

  init(match: PhotoMatch, action: String = "Log", log: @escaping ([MatchedItem]) -> Void) {
    self.log = log
    self.action = action
    _edit = State(initialValue: MealEdit(match))
  }

  init(recipe: Recipe?, save: @escaping (String, [MatchedItem]) -> Void) {
    self.init(match: PhotoMatch(mealId: "", items: recipe?.items ?? []), action: "Save") { _ in }
    (saveRecipe, _name) = (save, State(initialValue: recipe?.name ?? ""))
  }

  var body: some View {
    Group {
      if searching == .barcode {
        RecipeBarcode(target: $searching) { edit.add($0) }
      } else if let searching {
        search(searching)
      } else {
        list
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Theme.surface)
    .presentationDetents([.medium, .large], selection: $detent)
    .presentationDragIndicator(.visible)
    .onChange(of: searching) { _, target in if target != nil { detent = .large } }
  }

  private var list: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.spaceSm) {
        TopBar(
          title: saveRecipe == nil ? "Meal" : "Recipe",
          titleID: saveRecipe == nil ? "food.match.title" : "food.recipe.editor",
          action: .init(title: "Done", id: "food.edit.done") { dismiss() })
        if saveRecipe != nil {
          TextField("Name", text: $name).textStyle(.headline).padding(Theme.spaceMd)
            .background(RoundedRectangle(cornerRadius: Theme.radiusInner).fill(Theme.surfaceRaised))
            .onChange(of: name) { _, typed in name = String(typed.prefix(Recipe.maxName)) }
            .accessibilityIdentifier("food.recipe.name")
        }
        HStack(alignment: .top, spacing: Theme.spaceXl) {
          PhotoMatchSheet.total(
            "Energy", edit.totalKcal, unit: "kcal", spoken: "kcal", color: Theme.dataEnergy,
            id: "food.match.total.kcal")
          PhotoMatchSheet.total(
            "Protein", edit.totalProteinG, unit: "g", spoken: "g protein",
            color: Theme.dataProtein, id: "food.match.total.protein")
        }
        .padding(.bottom, Theme.spaceXs)
        ForEach(Array(edit.items.enumerated()), id: \.offset) { index, item in
          PhotoMatchSheet.row(item, id: "food.match.item.\(index)") {
            searching = .replace(index)
          } controls: {
            stepper(index, item, id: "food.match.item.\(index)")
          }
          .accessibilityElement(children: .contain).accessibilityIdentifier(
            "food.match.item.\(index)"
          )
          .accessibilityAction(named: "Remove") { edit.remove(index) }
          .simultaneousGesture(
            DragGesture(minimumDistance: Theme.spaceXl).onEnded { drag in
              let (dx, dy) = (drag.translation.width, drag.translation.height)
              if dx < -Theme.sizeTarget, abs(dx) > abs(dy) { withAnimation { edit.remove(index) } }
            })
        }
        wide("+ Add item", id: "food.edit.add", inverted: false) { searching = .add }
        if saveRecipe != nil {
          wide("Barcode", id: "food.recipe.barcode", inverted: false) { searching = .barcode }
        }
      }
      .padding(Theme.spaceLg)
    }
    .scrollIndicators(.hidden)
    // Log, full width and pinned under the list, so it stays on screen at the medium detent.
    .safeAreaInset(edge: .bottom, spacing: 0) {
      let id = saveRecipe == nil ? "food.edit.\(action.lowercased())" : "food.recipe.save"
      wide(action, id: id, inverted: true) {
        if let saveRecipe { saveRecipe(name, edit.items) } else { log(edit.items) }
      }
      .disabled(edit.items.isEmpty || (saveRecipe != nil && Recipe.name(name) == nil))
      .padding(Theme.spaceLg).background(Theme.surface)
    }
  }

  /// - and + around the serving count ("1.5"), in half steps (S-050).
  private func stepper(_ index: Int, _ item: MatchedItem, id: String) -> some View {
    HStack(spacing: 0) {
      step(index, up: false, id: id)
      Text(PhotoMatchSheet.count(item)).textStyle(.value).frame(minWidth: Theme.sizeTarget)
        .accessibilityIdentifier("\(id).count")
      step(index, up: true, id: id)
    }
  }

  private func step(_ index: Int, up: Bool, id: String) -> some View {
    Button {
      edit.step(index, up: up)
    } label: {
      Image(systemName: up ? "plus" : "minus").textStyle(.value, weight: .semibold)
        .foregroundStyle(Theme.ink).frame(width: Theme.sizeTarget, height: Theme.sizeTarget)
        .overlay(Circle().stroke(Theme.track))
    }
    .accessibilityLabel(up ? "Half serving more" : "Half serving less")
    .accessibilityIdentifier("\(id).\(up ? "plus" : "minus")")
  }

  /// A full-width pill: Log in `invert` at the bottom, + Add item in `surface-raised`.
  private func wide(
    _ title: String, id: String, inverted: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(title).textStyle(.headline)
        .foregroundStyle(inverted ? Theme.onInvert : Theme.ink)
        .frame(maxWidth: .infinity, minHeight: inverted ? Theme.sizeControl : Theme.sizeTarget)
        .background(Capsule().fill(inverted ? Theme.invert : Theme.surfaceRaised))
    }
    .accessibilityIdentifier(id)
  }

  /// The same search as the camera's (S-014), inside the sheet; a pick returns to the list.
  private func search(_ target: SearchTarget) -> some View {
    let text = query.trimmingCharacters(in: .whitespaces)
    return VStack(alignment: .leading, spacing: Theme.spaceSm) {
      HStack {
        TextField("Search food", text: $query).focused($focused).autocorrectionDisabled()
          .textStyle(.subtitle).foregroundStyle(Theme.ink)
          .padding(.horizontal, Theme.spaceLg).frame(height: Theme.sizeTarget)
          .background(Capsule().fill(Theme.surface))
          .accessibilityIdentifier("food.edit.search.field")
        Button("Cancel") { (searching, query) = (nil, "") }
          .foregroundStyle(Theme.ink).accessibilityIdentifier("food.edit.search.cancel")
      }
      if !text.isEmpty {
        FoodSearchPanel(query: text) { item in
          switch target {
          case .replace(let index): edit.replace(index, with: item)
          case .add, .barcode: edit.add(item)
          }
          focused = false
          (searching, query) = (nil, "")
        }
      }
    }
    .padding(Theme.spaceLg)
    .onAppear { focused = true }
  }
}
