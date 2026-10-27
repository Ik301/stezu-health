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
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      page {
        title("History", id: "workout.history.title")
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
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }.accessibilityIdentifier("workout.history.done")
        }
      }
    }
    .tint(Theme.ink)
  }

  /// One session: each exercise with its sets as weight x reps.
  private func detail(_ session: WorkoutSession) -> some View {
    page {
      title("\(name(session))   \(Self.day(session.startedAt))", id: "history.session.title")
      if continuable(session) {
        Button("Continue") { onContinue(session) }
          .textStyle(.headline)
          .frame(maxWidth: .infinity, minHeight: Theme.sizeControl)
          .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 1))
          .accessibilityIdentifier("history.session.continue")
      }
      ForEach(Array(session.exercises.enumerated()), id: \.offset) { index, log in
        VStack(alignment: .leading, spacing: Theme.spaceXs) {
          NavigationLink {
            exercise(log.exercise)
          } label: {
            Text(log.exercise).textStyle(.subtitle, weight: .semibold)
          }
          .accessibilityIdentifier("history.exercise.\(index)")
          Text(Self.sets(log.sets))
            .textStyle(.subtitle)
            .accessibilityIdentifier("history.exercise.\(index).sets")
        }
        .padding(Theme.spaceLg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.surface))
      }
    }
  }

  /// Every session with this exercise, newest first, with that session's sets of it.
  private func exercise(_ name: String) -> some View {
    page {
      title(name, id: "history.exercise.title")
      let past = WeeklyHistory.sessions(with: name, in: sessions)
      ForEach(Array(past.enumerated()), id: \.offset) { index, session in
        row("\(Self.day(session.startedAt))   \(Self.sets(session.sets(for: name) ?? []))")
          .accessibilityIdentifier("history.past.\(index)")
      }
    }
  }

  private func page(@ViewBuilder _ content: () -> some View) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.spaceMd, content: content).padding(Theme.spaceCard)
    }
    .scrollIndicators(.hidden)
    .buttonStyle(.plain)
    .foregroundStyle(Theme.ink)
    .background(Theme.ground.ignoresSafeArea())
  }

  private func title(_ text: String, id: String) -> some View {
    Text(text).textStyle(.title2).accessibilityIdentifier(id)
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
