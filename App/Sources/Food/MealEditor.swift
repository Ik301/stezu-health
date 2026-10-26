import StezuCore
import SwiftUI

/// The item list after a photo or a pick (S-015): tap a name to replace it, - and + in half
/// servings, Remove, + Add item, and the single Log button. Totals follow every edit (D-049).
struct MealEditor: View {
  let log: ([MatchedItem]) -> Void
  @State private var edit: MealEdit
  @State private var searching: SearchTarget?
  @State private var query = ""
  @State private var detent = PresentationDetent.medium
  @FocusState private var focused: Bool

  /// What a search pick does: take an item's place, or join the list.
  enum SearchTarget: Equatable {
    case replace(Int)
    case add
  }

  init(match: PhotoMatch, log: @escaping ([MatchedItem]) -> Void) {
    self.log = log
    _edit = State(initialValue: MealEdit(match))
  }

  var body: some View {
    Group {
      if let searching { search(searching) } else { list }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Theme.background)
    .presentationDetents([.medium, .large], selection: $detent)
    .onChange(of: searching) { _, target in if target != nil { detent = .large } }
  }

  private var list: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text("Meal").font(.system(size: Theme.subtitleSize, weight: .semibold))
            .accessibilityIdentifier("food.match.title")
          Spacer()
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
          pill("Log", id: "food.edit.log", inverted: true) { log(edit.items) }
            .disabled(edit.items.isEmpty)
        }
      }
      .padding(16)
    }
  }

  private func stepper(_ index: Int, id: String) -> some View {
    HStack(spacing: 8) {
      ForEach([false, true], id: \.self) { up in
        Button {
          edit.step(index, up: up)
        } label: {
          Image(systemName: up ? "plus" : "minus").font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.text).frame(width: 36, height: 32)
            .background(Capsule().fill(Color.white))
        }
        .accessibilityLabel(up ? "Half serving more" : "Half serving less")
        .accessibilityIdentifier("\(id).\(up ? "plus" : "minus")")
      }
      Spacer()
      Button("Remove") { edit.remove(index) }
        .font(.system(size: Theme.labelSize, weight: .medium)).foregroundStyle(Theme.label)
        .accessibilityIdentifier("\(id).remove")
    }
  }

  private func pill(
    _ title: String, id: String, inverted: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(title, action: action)
      .font(.system(size: Theme.subtitleSize, weight: .semibold))
      .foregroundStyle(inverted ? Theme.invertedText : Theme.text)
      .padding(.horizontal, 22).frame(height: 44)
      .background(Capsule().fill(inverted ? Theme.invertedCard : Color.white))
      .accessibilityIdentifier(id)
  }

  /// The same search as the camera's (S-014), inside the sheet; a pick returns to the list.
  private func search(_ target: SearchTarget) -> some View {
    let text = query.trimmingCharacters(in: .whitespaces)
    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField("Search food", text: $query).focused($focused).autocorrectionDisabled()
          .font(.system(size: Theme.subtitleSize)).foregroundStyle(Theme.text)
          .padding(.horizontal, 16).frame(height: 44).background(Capsule().fill(Theme.card))
          .accessibilityIdentifier("food.edit.search.field")
        Button("Cancel") { (searching, query) = (nil, "") }
          .foregroundStyle(Theme.text).accessibilityIdentifier("food.edit.search.cancel")
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
    .padding(16)
    .onAppear { focused = true }
  }
}
