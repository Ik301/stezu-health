import StezuCore
import SwiftUI

/// What Finish opens (S-044, S-045): Undo on top for 8 s, the date and times, duration, working
/// sets, volume and an In Health tag, then each exercise's sets and its best set against the
/// last session of the same template, in plain ink (D-032). Done is in the TopBar.
struct WorkoutSummaryView: View {
  let summary: WorkoutSummary
  let inHealth: Bool
  let undo: () -> Void
  @State private var canUndo = true

  var body: some View {
    let name = summary.logger.template.name
    let volume = WorkoutSummary.volume(summary.done.session).map {
      Int($0.rounded()).formatted(.number.locale(Locale(identifier: "en_US"))) + " lb"
    }
    let seconds = Int(summary.done.endedAt.timeIntervalSince(summary.done.session.startedAt))
    let start = summary.done.session.startedAt
    let day = start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    let times = "\(DayTimelineView.clock(start)) to \(DayTimelineView.clock(summary.done.endedAt))"
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.spaceMd) {
        if canUndo {
          HStack {
            Text("\(name) saved, \(inHealth ? "in Health" : "not in Health")")
            Spacer()
            Button("Undo", action: undo).textStyle(.headline).frame(minHeight: Theme.sizeTarget)
              .accessibilityIdentifier("workout.summary.undo")
          }
          .textStyle(.subtitle).foregroundStyle(Theme.onInvert).padding(.horizontal, Theme.spaceLg)
          .background(Capsule().fill(Theme.invert))
        }
        Text("\(day), \(times)").textStyle(.label).foregroundStyle(Theme.muted)
          .accessibilityIdentifier("workout.summary.when")
        VStack(alignment: .leading, spacing: Theme.spaceMd) {
          HStack(alignment: .top) {
            stat("Duration", seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min", id: "duration")
            stat("Working sets", "\(summary.done.workingSets)", id: "sets")
            stat("Volume", volume ?? "--", id: "volume")
          }
          Text(inHealth ? "In Health" : "Not in Health")
            .textStyle(.axis).foregroundStyle(Theme.muted)
            .padding(.horizontal, Theme.spaceSm).padding(.vertical, Theme.space2xs)
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusChip).strokeBorder(Theme.track))
            .accessibilityIdentifier("workout.summary.health")
        }
        .padding(Theme.spaceLg).background(card)
        VStack(alignment: .leading, spacing: Theme.spaceMd) {
          Text(
            summary.lastSessionAt.map { (last: Date) -> String in
              let days = WorkoutSummary.days(from: last, to: summary.done.session.startedAt)
              return "Exercises vs last \(name), \(days == 0 ? "today" : "\(days)d ago")"
            } ?? "Exercises, no earlier \(name)"
          )
          .textStyle(.label).foregroundStyle(Theme.muted)
          .accessibilityIdentifier("workout.summary.versus")
          ForEach(Array(summary.exercises.enumerated()), id: \.offset) { index, result in
            HStack(alignment: .firstTextBaseline) {
              VStack(alignment: .leading, spacing: Theme.space2xs) {
                Text(result.exercise).textStyle(.headline)
                Text(result.sets.map(Self.set).joined(separator: ", ")).textStyle(.label)
                  .foregroundStyle(Theme.muted)
              }
              .accessibilityElement(children: .combine)
              .accessibilityIdentifier("workout.summary.exercise.\(index)")
              Spacer()
              Text(result.change ?? "--").textStyle(.subtitle)
                .accessibilityIdentifier("workout.summary.change.\(index)")
            }
          }
        }
        .padding(Theme.spaceLg).background(card)
      }
      .foregroundStyle(Theme.ink)
    }
    .scrollIndicators(.hidden)
    .task(id: summary.done.endedAt) {
      canUndo = true
      try? await Task.sleep(for: .seconds(WorkoutSummary.undoWindow))
      if !Task.isCancelled { canUndo = false }
    }
  }

  private var card: some View {
    RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.surface)
  }

  private func stat(_ label: String, _ value: String, id: String) -> some View {
    VStack(alignment: .leading, spacing: Theme.spaceXs) {
      Text(label).textStyle(.label).foregroundStyle(Theme.muted)
      Text(value).textStyle(.value).accessibilityIdentifier("workout.summary.\(id)")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// "60 x 8", or "BW x 12" for a bodyweight set.
  static func set(_ set: WorkoutSet) -> String {
    "\(set.pounds.map { String(format: "%g", $0) } ?? "BW") x \(set.reps)"
  }
}
