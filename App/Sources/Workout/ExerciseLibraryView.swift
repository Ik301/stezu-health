import StezuCore
import SwiftUI

/// The Exercises library (S-007): search, New exercise (the only keyboard form in Workout), and
/// the exercises grouped by muscle with when each was last done. A tap on a row calls `pick`.
struct ExerciseLibraryView: View {
  let history: [WorkoutSession]
  let pick: (LibraryExercise) -> Void
  @Environment(\.appEnvironment) private var environment
  @State private var library = ExerciseLibrary()
  @State private var query = ""
  @State private var adding = false
  @State private var fields = ["", "", "", ""]  // name, equipment, muscle, rest seconds

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Text("Exercises")
          .font(.system(size: 28, weight: .semibold))
          .accessibilityIdentifier("workout.library.title")
        field("Search", text: $query, id: "workout.library.search")
        if adding {
          form
        } else {
          Button("New exercise") { adding = true }
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .overlay(Capsule().strokeBorder(Theme.text, lineWidth: 1))
            .accessibilityIdentifier("workout.library.new")
        }
        ForEach(library.groupedByMuscle(query), id: \.muscle) { group in
          Text(group.muscle)
            .font(.system(size: Theme.labelSize))
            .foregroundStyle(Theme.label)
          ForEach(group.exercises, id: \.key) { row($0) }
        }
      }
      .padding(20)
    }
    .buttonStyle(.plain)
    .foregroundStyle(Theme.text)
    .background(Theme.background.ignoresSafeArea())
    .onAppear { library = ExerciseLibraryStore(storage: environment.storage).load() }
  }

  private func row(_ exercise: LibraryExercise) -> some View {
    let last = ExerciseLibrary.lastDone(exercise.name, before: Date(), in: history)
    return Button {
      pick(exercise)
    } label: {
      HStack {
        Text(exercise.name).font(.system(size: Theme.subtitleSize))
        Spacer()
        Text((exercise.isCustom ? "Custom   " : "") + last)
          .font(.system(size: Theme.labelSize))
          .foregroundStyle(Theme.label)
      }
      .padding(16)
      .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.card))
    }
    .accessibilityLabel(exercise.isCustom ? "\(exercise.name), custom" : exercise.name)
    .accessibilityValue(last)
    .accessibilityIdentifier("workout.library.row.\(exercise.key)")
  }

  private var form: some View {
    VStack(spacing: 8) {
      field("Name", text: $fields[0], id: "workout.library.custom.name")
      field("Equipment", text: $fields[1], id: "workout.library.custom.equipment")
      field("Muscle", text: $fields[2], id: "workout.library.custom.muscle")
      field("Rest seconds", text: $fields[3], id: "workout.library.custom.rest")
        .keyboardType(.numberPad)
      Button("Save") { save() }
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(Theme.invertedText)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Capsule().fill(Theme.invertedCard))
        .accessibilityIdentifier("workout.library.custom.save")
    }
  }

  private func field(_ title: String, text: Binding<String>, id: String) -> some View {
    TextField(title, text: text).textFieldStyle(.roundedBorder).autocorrectionDisabled()
      .accessibilityIdentifier(id)
  }

  /// Adds and saves the custom exercise, then searches for it so it shows at the top. Does
  /// nothing until there is a name and a rest.
  private func save() {
    guard let seconds = Int(fields[3]),
      let added = library.addCustom(
        name: fields[0], equipment: fields[1], muscle: fields[2], restSeconds: seconds)
    else { return }
    ExerciseLibraryStore(storage: environment.storage).save(library)
    (adding, fields, query) = (false, ["", "", "", ""], added.name)
  }
}

/// The bundled ExerciseLibrary.json plus the custom exercises, saved as one JSON file. Memory
/// storage keeps nothing, so every `-uitest` launch starts from the bundled list.
struct ExerciseLibraryStore {
  let file: URL?

  init(storage: StorageMode) {
    file = WorkoutSessionStore(storage: storage).file?.deletingLastPathComponent()
      .appendingPathComponent("custom-exercises.json")
  }

  func load(bundle: Bundle = .main) -> ExerciseLibrary {
    let url = bundle.url(forResource: "ExerciseLibrary", withExtension: "json")
    let bundled = url.flatMap { try? Data(contentsOf: $0) }
    let saved = file.flatMap { try? Data(contentsOf: $0) }
    let seed = bundled.flatMap { try? JSONDecoder().decode(ExerciseLibrary.self, from: $0) }
    let custom = saved.flatMap { try? JSONDecoder().decode([LibraryExercise].self, from: $0) }
    return ExerciseLibrary(exercises: (seed?.exercises ?? []) + (custom ?? []))
  }

  func save(_ library: ExerciseLibrary) {
    guard let file, let data = try? JSONEncoder().encode(library.custom) else { return }
    try? FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: file, options: .atomic)
  }
}
