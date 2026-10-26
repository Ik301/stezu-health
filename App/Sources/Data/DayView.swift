import StezuCore
import SwiftUI

/// Everything recorded on one day (S-025), in the story's order, each with its source. Stezu's
/// own weigh-ins, meals and sessions can be deleted (a second tap confirms) and meals edited;
/// Health's records are read-only. A day with nothing recorded shows "--".
struct DayView: View {
  let day: Date
  @Environment(\.appEnvironment) private var environment
  @State private var records: [DayRecord]?
  @State private var meals: [LoggedMeal] = []
  /// Deleted this visit; a scenario's seeded meals and sessions live only in memory.
  @State private var removed: [DayRecord.Owner] = []
  @State private var confirming: Int?
  @State private var editing: LoggedMeal?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if records?.isEmpty == true { Text("--").accessibilityIdentifier("day.empty") }
      ForEach(Array((records ?? []).enumerated()), id: \.offset) { index, record in
        row(record, id: "day.record.\(index)", index: index)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .task { await load() }
    .sheet(item: $editing) { meal in
      MealEditor(match: PhotoMatch(mealId: meal.id.uuidString, items: meal.items)) { items in
        Task { await save(LoggedMeal(id: meal.id, loggedAt: meal.loggedAt, items: items)) }
      }
    }
  }

  private func row(_ record: DayRecord, id: String, index: Int) -> some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 2) {
        Text(record.kind.rawValue).font(.system(size: 17, weight: .semibold))
          .accessibilityIdentifier(id)
        Text(record.detail).font(.system(size: Theme.subtitleSize))
          .accessibilityIdentifier("\(id).detail")
        Text(record.isStezu ? "From Stezu" : "From \(record.source), read-only")
          .font(.system(size: Theme.labelSize)).foregroundStyle(Theme.label)
          .accessibilityIdentifier("\(id).source")
      }
      Spacer()
      if case .meal(let mealID) = record.owner, let meal = meals.first(where: { $0.id == mealID }) {
        action("Edit", id: "\(id).edit") { editing = meal }
      }
      if record.isStezu {
        action(confirming == index ? "Confirm" : "Delete", id: "\(id).delete") {
          if confirming == index { Task { await delete(record.owner) } } else { confirming = index }
        }
      }
    }
  }

  private func action(_ title: String, id: String, run: @escaping () -> Void) -> some View {
    Button(title, action: run).font(.system(size: Theme.labelSize, weight: .medium))
      .foregroundStyle(Theme.text).padding(.horizontal, 12).frame(minHeight: 32)
      .background(Color.white, in: Capsule()).accessibilityIdentifier(id)
  }

  /// Logged meals (a saved edit replaces a seeded meal with its id), Stezu sessions from the
  /// seeded history and finished-workouts.json, and Health.
  private func load() async {
    let stored = await environment.mealCaptures.logged()
    let seeded = environment.mealHistory.filter { meal in !stored.contains { $0.id == meal.id } }
    meals = (stored + seeded).filter { !removed.contains(.meal($0.id)) }
    let finished = FinishedWorkoutStore(storage: environment.storage).load().map(\.session)
    let sessions = (environment.workoutHistory + finished)
      .filter { !removed.contains(.session($0.startedAt)) }
    records = await DayRecords.load(
      day, from: environment.healthStore, meals: meals, sessions: sessions)
  }

  /// A weigh-in leaves Health; a meal's `.log` file and a session's entry in
  /// finished-workouts.json are removed. A failed Health delete keeps the record.
  private func delete(_ owner: DayRecord.Owner) async {
    confirming = nil
    switch owner {
    case .weighIn(let date):
      guard (try? await environment.healthStore.deleteBodyMass(at: date)) != nil else { return }
    case .meal(let id):
      await environment.mealCaptures.unlog(id)
      await environment.syncMeal(nil, id: id)
    case .session(let start):
      let store = FinishedWorkoutStore(storage: environment.storage)
      store.save(store.load().filter { $0.session.startedAt != start })
    case .health:
      return
    }
    removed.append(owner)
    await load()
  }

  private func save(_ meal: LoggedMeal) async {
    editing = nil
    if (try? await environment.mealCaptures.log(meal)) != nil {
      await environment.syncMeal(meal, id: meal.id, edited: true)
    }
    await load()
  }
}
