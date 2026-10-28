import StezuCore
import SwiftUI

/// Everything recorded on one day (S-025), in the story's order, each with its source. Stezu's
/// own weigh-ins, meals and sessions can be deleted (a second tap confirms) and meals edited;
/// Health's records are read-only. A day with nothing recorded shows "--".
struct DayView: View {
  @Binding var day: Date
  @Environment(\.appEnvironment) private var environment
  @State private var records: [DayRecord]?
  @State private var meals: [LoggedMeal] = []
  @State private var sessions: [WorkoutSession] = []
  @State private var night: SleepNight?
  @State private var places: [PlaceRecord] = []  // the day's visits
  @State private var names: [String: String] = [:]  // S-049: by visit id, on the phone only
  @State private var sleepOpen = false
  /// Deleted this visit; a scenario's seeded meals and sessions live only in memory.
  @State private var removed: [DayRecord.Owner] = []
  @State private var confirming: Int?
  @State private var editing: LoggedMeal?
  private let shape = RoundedRectangle(cornerRadius: Theme.radiusCard)

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: Theme.spaceMd) {
        let cells = summary
        Grid(
          alignment: .topLeading, horizontalSpacing: Theme.spaceMd, verticalSpacing: Theme.spaceMd
        ) {
          ForEach([0, 2], id: \.self) { row in
            GridRow {
              cell(cells[row])
              cell(cells[row + 1])
            }
          }
        }
        .padding(Theme.spaceLg).background(Theme.surface, in: shape)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("day.summary")
        DayTimelineView(
          day: day, marks: marks { proxy.scrollTo("day.record.\($0)", anchor: .top) },
          visits: places.compactMap { place in
            guard let from = place.times.first, let to = place.times.last else { return nil }
            return .init(span: DateInterval(start: from, end: to), name: names[place.id])
          }
        )
        .padding(Theme.spaceMd).background(Theme.surface, in: shape)
        .sheet(isPresented: $sleepOpen) { [day] in
          SleepDetailView(night: Calendar.current.startOfDay(for: day))
        }
        VStack(alignment: .leading, spacing: Theme.spaceMd) {
          if records?.isEmpty == true { Text("--").accessibilityIdentifier("day.empty") }
          ForEach(Array((records ?? []).enumerated()), id: \.offset) { index, record in
            row(record, id: "day.record.\(index)", index: index).id("day.record.\(index)")
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spaceLg).background(Theme.surface, in: shape)
      }
    }
    .task(id: day) { await load() }
    .sheet(item: $editing) { meal in
      MealEditor(match: PhotoMatch(mealId: meal.id.uuidString, items: meal.items)) { items in
        Task { await save(LoggedMeal(id: meal.id, loggedAt: meal.loggedAt, items: items)) }
      }
    }
  }

  /// S-041, S-049: the day's totals as Slept, Food, Training and Steps; "--" for what is missing.
  private var summary: [(name: String, value: String, unit: String, more: String?)] {
    let all = records ?? []
    let eaten = meals.filter { Calendar.current.isDate($0.loggedAt, inSameDayAs: day) }
    let total = { (part: KeyPath<MatchedItem, FoodRange?>) in
      range(FoodRange.total(eaten.flatMap(\.items).map { $0[keyPath: part] }))
    }
    let trained = all.compactMap { session($0) }
    let sets = trained.reduce(0) { $0 + $1.workingSets }
    let steps = all.first { $0.kind == .steps }.flatMap { Int($0.detail)?.formatted() }
    return [
      ("Slept", night.map { hm($0.asleep) } ?? "--", "", nil),
      ("Food", total(\.kcal), "kcal", "\(total(\.proteinG)) g protein"),
      ("Training", trained.first.map { name($0) } ?? "--", "\(sets) sets", nil),
      ("Steps", steps ?? "--", "", nil),
    ]
  }

  /// A summary cell: its name small, the value large and its unit small; "--" has no unit.
  private func cell(_ cell: (name: String, value: String, unit: String, more: String?)) -> some View
  {
    let known = cell.value != "--"
    return VStack(alignment: .leading, spacing: Theme.space2xs) {
      Text(cell.name).textStyle(.label).foregroundStyle(Theme.muted)
      HStack(alignment: .firstTextBaseline, spacing: Theme.spaceXs) {
        Text(cell.value).textStyle(.value, weight: .medium)
        if known { Text(cell.unit).textStyle(.label).foregroundStyle(Theme.muted) }
      }
      if known, let more = cell.more { Text(more).textStyle(.label).foregroundStyle(Theme.muted) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      [cell.name, cell.value, known ? cell.unit : ""].filter { !$0.isEmpty }.joined(separator: " ")
        + (known ? cell.more.map { ", \($0)" } ?? "" : "")
    )
    .accessibilityIdentifier("day.summary.\(cell.name.lowercased())")
  }

  /// The night, then each weigh-in, meal and workout; a tap scrolls the list to its record.
  private func marks(_ scroll: @escaping (Int) -> Void) -> [DayTimelineView.Mark] {
    let clock = DayTimelineView.clock
    var marks: [DayTimelineView.Mark] = []
    if let night {
      let span = DateInterval(start: night.bedtime, end: night.wake)
      let at = { (date: Date) in date.timeIntervalSince(span.start) / span.duration }
      let stripe = night.stages.sorted { $0.start < $1.start }.flatMap { stage in
        [stage.start, stage.end].map {
          Gradient.Stop(color: SleepDetailView.color(stage.lane), location: at($0))
        }
      }
      let detail = "\(clock(span.start)) to \(clock(span.end)), \(hm(night.asleep)) asleep"
      marks.append(
        .init(id: "day.timeline.sleep", title: "Sleep", detail: detail, span: span, stripe: stripe)
        { sleepOpen = true })
    }
    let all = records ?? []
    for (index, record) in all.enumerated() where [.weighIn, .meal, .workout].contains(record.kind)
    {
      let (logged, kind) = (session(record), record.kind.rawValue.lowercased())
      let items = meals.first { record.owner == .meal($0.id) }?.items ?? []
      let end = logged?.exercises.flatMap(\.sets).map(\.loggedAt).max() ?? record.time
      marks.append(
        DayTimelineView.Mark(
          id: "day.timeline.\(kind).\(all[..<index].filter { $0.kind == record.kind }.count)",
          title: logged.map { name($0) }
            ?? (items.isEmpty ? record.kind.rawValue : items.map(\.name).joined(separator: ", ")),
          detail: "\(clock(record.time)), "
            + (logged.map { "\($0.workingSets) working sets" }
              ?? (items.isEmpty
                ? record.detail : range(FoodRange.total(items.map(\.kcal))) + " kcal")),
          span: DateInterval(start: record.time, end: max(record.time, end)),
          stripe: record.kind == .meal ? [Gradient.Stop(color: Theme.dataEnergy, location: 0)] : []
        ) { scroll(index) })
    }
    return marks
  }

  private func session(_ record: DayRecord) -> WorkoutSession? {
    sessions.first { record.owner == .session($0.startedAt) }
  }

  private func name(_ session: WorkoutSession) -> String {
    session.templateKey.flatMap { environment.workoutNames().templates[$0] } ?? "Workout"
  }

  private func range(_ range: FoodRange?) -> String { FoodRange.text(range) }

  private func hm(_ seconds: TimeInterval) -> String {
    let minutes = Int((seconds / 60).rounded())
    return "\(minutes / 60)h \(minutes % 60)m"
  }

  private func row(_ record: DayRecord, id: String, index: Int) -> some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: Theme.space2xs) {
        Text(record.kind.rawValue).textStyle(.headline)
          .accessibilityIdentifier(id)
        Text(record.detail).textStyle(.subtitle)
          .accessibilityIdentifier("\(id).detail")
        Text(record.isStezu ? "From Stezu" : "From \(record.source), read-only")
          .textStyle(.label).foregroundStyle(Theme.muted)
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
    Button(title, action: run).textStyle(.label, weight: .medium)
      .foregroundStyle(Theme.ink).padding(.horizontal, Theme.spaceMd).frame(minHeight: 32)
      .background(Theme.surfaceRaised, in: Capsule()).accessibilityIdentifier(id)
  }

  /// Logged meals (a saved edit replaces a seeded meal with its id), Stezu sessions from the
  /// seeded history and finished-workouts.json, and Health.
  private func load() async {
    let stored = await environment.mealCaptures.logged()
    let seeded = environment.mealHistory.filter { meal in !stored.contains { $0.id == meal.id } }
    meals = (stored + seeded).filter { !removed.contains(.meal($0.id)) }
    let finished = FinishedWorkoutStore(storage: environment.storage).load().map(\.session)
    sessions = (environment.workoutHistory + finished)
      .filter { !removed.contains(.session($0.startedAt)) }
    records = await DayRecords.load(
      day, from: environment.weightHealth, meals: meals, sessions: sessions)
    let start = Calendar.current.startOfDay(for: day)
    night = await SleepDetail.load(from: environment.healthStore, now: day).nights[start]
    places = await environment.places.log.places.filter { place in
      guard place.at == nil, let from = place.times.first, let to = place.times.last else {
        return false
      }
      return to >= start && from < start + 86_400
    }
    // D-119: looked up only while the app is open, once a visit; the names stay on the phone.
    if UIApplication.shared.applicationState == .active {
      names = await environment.placeNames.name(places)
    }
  }

  /// A weigh-in leaves the phone, then Health, then is sent as deleted (S-031); a meal's `.log`
  /// file and a session's entry in finished-workouts.json are removed.
  private func delete(_ owner: DayRecord.Owner) async {
    confirming = nil
    switch owner {
    case .weighIn(let date):
      await environment.deleteWeighIn(at: date)
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

/// S-049: the previous and next day, in the TopBar's row above the date (1 tap per day).
struct DayArrows: View {
  @Binding var day: Date
  @Environment(\.appEnvironment) private var environment

  var body: some View {
    HStack(spacing: 0) {
      ForEach([-1, 1], id: \.self) { step in
        Button {
          day = Calendar.current.date(byAdding: .day, value: step, to: day) ?? day
        } label: {
          Image(systemName: step < 0 ? "chevron.left" : "chevron.right").textStyle(.value)
            .frame(width: Theme.sizeTarget, height: Theme.sizeTarget)
        }
        .accessibilityLabel(step < 0 ? "Previous day" : "Next day")
        .accessibilityIdentifier(step < 0 ? "day.previous" : "day.next")
        .disabled(step > 0 && Calendar.current.startOfDay(for: day) + 86_400 > environment.now())
      }
    }
    .buttonStyle(.plain).foregroundStyle(Theme.ink)
  }
}
