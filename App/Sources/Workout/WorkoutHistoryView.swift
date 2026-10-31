import StezuCore
import SwiftUI

/// Workout history (S-010): Monday-to-Sunday weeks that have a session, newest first, each with
/// its sessions and working-set count. A session opens its exercises and sets; an exercise opens
/// every session that has it, newest first. Nothing is stored here; a session that can still
/// be continued (S-036) shows Continue, which hands it back to the Workout screen.
struct WorkoutHistoryView: View {
  let sessions: [WorkoutSession]
  /// Template names by key; a session with no known template shows as "Workout".
  let names: [String: String]
  var continuable: (WorkoutSession) -> Bool = { _ in false }
  var onContinue: (WorkoutSession) -> Void = { _ in }
  /// S-055: whether a session's sets can be changed (a finished one), and what a change does.
  var editable: (WorkoutSession) -> Bool = { _ in false }
  var onEdit: (PastSet, SetEdit) -> Void = { _, _ in }

  var body: some View {
    NavigationStack {
      HistoryPage(
        title: "History", id: "workout.history.title", rung: "Done",
        rungID: "workout.history.done"
      ) {
        let weeks = WeeklyHistory.weeks(sessions)
        if weeks.isEmpty {
          Text("No sessions yet").foregroundStyle(Theme.muted)
        }
        ForEach(Array(weeks.enumerated()), id: \.offset) { w, week in
          HStack {
            Text("\(Self.day(week.start)) - \(Self.day(week.end))")
              .accessibilityIdentifier("history.week.\(w)")
            Spacer()
            Text(Self.count(week.workingSets, "working set"))
              .accessibilityIdentifier("history.week.\(w).sets")
          }
          .textStyle(.label)
          .foregroundStyle(Theme.muted)
          .padding(.top, Theme.spaceSm)
          ForEach(Array(week.sessions.enumerated()), id: \.offset) { s, session in
            NavigationLink {
              detail(session)
            } label: {
              row(
                "\(name(session))   \(Self.day(session.startedAt))   "
                  + Self.count(session.workingSets, "set"))
            }
            .accessibilityIdentifier("history.session.\(w).\(s)")
          }
        }
      }
    }
    .tint(Theme.ink)
    .presentationDragIndicator(.visible)
  }

  /// One session: each exercise with its sets as weight x reps.
  private func detail(_ session: WorkoutSession) -> some View {
    HistoryPage(
      title: "\(name(session))   \(Self.day(session.startedAt))", id: "history.session.title",
      rung: "History", rungID: "history.session.back"
    ) {
      if continuable(session) {
        Button("Continue") { onContinue(session) }
          .textStyle(.headline)
          .frame(maxWidth: .infinity, minHeight: Theme.sizeControl)
          .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 1))
          .accessibilityIdentifier("history.session.continue")
      }
      if editable(session) {  // S-055: a finished session's sets are chips that open SetEditor
        EditableSets(session: session, save: onEdit) { index, log, chips in
          card(index, log.exercise, rung: name(session)) { chips }
        }
      } else {
        ForEach(Array(session.exercises.enumerated()), id: \.offset) { index, log in
          card(index, log.exercise, rung: name(session)) {
            Text(Self.sets(log.sets))
              .textStyle(.subtitle)
              .accessibilityIdentifier("history.exercise.\(index).sets")
          }
        }
      }
    }
  }

  /// One exercise of a session: its name, which opens its past sessions, then its sets.
  private func card<Sets: View>(
    _ index: Int, _ exercise: String, rung: String, @ViewBuilder sets: () -> Sets
  ) -> some View {
    VStack(alignment: .leading, spacing: Theme.spaceXs) {
      NavigationLink {
        self.exercise(exercise, rung: rung)
      } label: {
        Text(exercise).textStyle(.subtitle, weight: .semibold)
      }
      .accessibilityIdentifier("history.exercise.\(index)")
      sets()
    }
    .padding(Theme.spaceLg)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.surface))
  }

  /// Every session with this exercise, newest first, with that session's sets of it.
  private func exercise(_ name: String, rung: String) -> some View {
    HistoryPage(
      title: name, id: "history.exercise.title", rung: rung, rungID: "history.exercise.back"
    ) {
      let past = WeeklyHistory.sessions(with: name, in: sessions)
      ForEach(Array(past.enumerated()), id: \.offset) { index, session in
        row("\(Self.day(session.startedAt))   \(Self.sets(session.sets(for: name) ?? []))")
          .accessibilityIdentifier("history.past.\(index)")
      }
    }
  }

  private func row(_ text: String) -> some View {
    Text(text)
      .textStyle(.subtitle)
      .padding(Theme.spaceLg)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.surface))
  }

  private func name(_ session: WorkoutSession) -> String {
    session.templateKey.flatMap { names[$0] } ?? "Workout"
  }

  static func day(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
  }

  static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

  /// "65 x 5, 60 x 8"; a bodyweight set is "BW x 10".
  static func sets(_ sets: [WorkoutSet]) -> String {
    sets.map { "\($0.pounds.map { String(format: "%g", $0) } ?? "BW") x \($0.reps)" }
      .joined(separator: ", ")
  }
}

/// One History page under its TopBar. The rung on the right goes back a page, or closes the
/// sheet on the first page (`dismiss` does either); the navigation bar stays hidden.
private struct HistoryPage<Content: View>: View {
  let title: String
  let id: String
  let rung: String
  let rungID: String
  @ViewBuilder let content: Content
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.spaceMd) {
        TopBar(title: title, titleID: id, action: .init(title: rung, id: rungID) { dismiss() })
        content
      }
      .padding(Theme.spaceCard)
    }
    .scrollIndicators(.hidden)
    .buttonStyle(.plain)
    .foregroundStyle(Theme.ink)
    .background(Theme.ground.ignoresSafeArea())
    .toolbar(.hidden, for: .navigationBar)
  }
}

/// S-055: a finished session's exercises with their sets as chips; a tap opens SetEditor. The
/// page keeps its own copy, so a saved change shows at once, and `save` keeps it.
private struct EditableSets<Card: View>: View {
  @State var session: WorkoutSession
  let save: (PastSet, SetEdit) -> Void
  let card: (Int, ExerciseLog, SetChips) -> Card
  @State private var editing: PastSet?

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spaceMd) {
      ForEach(Array(session.exercises.enumerated()), id: \.offset) { index, log in
        card(
          index, log,
          SetChips(sets: log.sets, id: "history.set.\(index)") { set in
            editing = PastSet(
              sessionStart: session.startedAt, exercise: log.exercise, number: set + 1,
              set: log.sets[set])
          })
      }
    }
    .sheet(item: $editing) { past in
      SetEditor(past: past) { edit in
        editing = nil
        guard let edit, session.apply(edit, toSetAt: past.set.loggedAt) != nil else { return }
        save(past, edit)
      }
    }
  }
}
