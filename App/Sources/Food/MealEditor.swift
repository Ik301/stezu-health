import StezuCore
import SwiftUI

/// The item list after a photo or a pick (S-015): tap a name to replace it, - and + in half
/// servings, Remove, + Add item, and the single Log button. Totals follow every edit (D-049).
struct MealEditor: View {
  let log: ([MatchedItem]) -> Void
  /// The button's title: "Log" after a photo or pick, "Save" for a meal from history (S-019).
  let action: String
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
  }

  init(match: PhotoMatch, action: String = "Log", log: @escaping ([MatchedItem]) -> Void) {
    self.log = log
    self.action = action
    _edit = State(initialValue: MealEdit(match))
  }

  var body: some View {
    Group {
      if let searching { search(searching) } else { list }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Theme.ground)
    .presentationDetents([.medium, .large], selection: $detent)
    .presentationDragIndicator(.visible)
    .onChange(of: searching) { _, target in if target != nil { detent = .large } }
  }

  private var list: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.spaceSm) {
        TopBar(
          title: "Meal", titleID: "food.match.title",
          action: .init(title: "Done", id: "food.edit.done") { dismiss() })
        HStack(spacing: Theme.spaceMd) {
          Text(PhotoMatchSheet.range(edit.totalKcal, unit: "kcal"))
            .accessibilityIdentifier("food.match.total.kcal")
          Text(PhotoMatchSheet.range(edit.totalProteinG, unit: "g protein"))
            .accessibilityIdentifier("food.match.total.protein")
        }
        ForEach(Array(edit.items.enumerated()), id: \.offset) { index, item in
          PhotoMatchSheet.row(item, id: "food.match.item.\(index)") {
            searching = .replace(index)
          } controls: {
            stepper(index, id: "food.match.item.\(index)")
          }
        }
        HStack {
          pill("+ Add item", id: "food.edit.add", inverted: false) { searching = .add }
          Spacer()
          pill(action, id: "food.edit.\(action.lowercased())", inverted: true) { log(edit.items) }
            .disabled(edit.items.isEmpty)
        }
      }
      .padding(Theme.spaceLg)
    }
    .scrollIndicators(.hidden)
  }

  private func stepper(_ index: Int, id: String) -> some View {
    HStack(spacing: Theme.spaceSm) {
      ForEach([false, true], id: \.self) { up in
        Button {
          edit.step(index, up: up)
        } label: {
          Image(systemName: up ? "plus" : "minus").textStyle(.subtitle, weight: .semibold)
            .foregroundStyle(Theme.ink).frame(width: 36, height: 32)
            .background(Capsule().fill(Theme.surfaceRaised))
        }
        .accessibilityLabel(up ? "Half serving more" : "Half serving less")
        .accessibilityIdentifier("\(id).\(up ? "plus" : "minus")")
      }
      Spacer()
      Button("Remove") { edit.remove(index) }
        .textStyle(.label, weight: .medium).foregroundStyle(Theme.muted)
        .accessibilityIdentifier("\(id).remove")
    }
  }

  private func pill(
    _ title: String, id: String, inverted: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(title, action: action)
      .textStyle(.subtitle, weight: .semibold)
      .foregroundStyle(inverted ? Theme.onInvert : Theme.ink)
      .padding(.horizontal, Theme.spaceXl).frame(height: Theme.sizeTarget)
      .background(Capsule().fill(inverted ? Theme.invert : Theme.surfaceRaised))
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
          case .add: edit.add(item)
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
