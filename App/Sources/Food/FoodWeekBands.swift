import StezuCore
import SwiftUI

/// This week on Food Today (S-043): the last 7 days, each one low-to-high kcal band in the energy
/// colour, today at full strength and marked "so far". A day with nothing logged is a dashed slot
/// with "--", never a zero bar. No target line (D-032). Each day is `<id>.<index>`, 6 for today.
struct FoodWeekBands: View {
  struct Day {
    let day: Date
    let kcal: FoodRange?
  }

  let days: [Day]
  let id: String

  var body: some View {
    let top = max(days.compactMap { $0.kcal?.high }.max() ?? 1, 1) * 1.1
    VStack(alignment: .leading, spacing: Theme.spaceSm) {
      HStack {
        Text("This week, kcal").textStyle(.subtitle, weight: .semibold).foregroundStyle(Theme.ink)
        Spacer()
        Text("logged \(days.filter { $0.kcal != nil }.count) of \(days.count) days")
          .textStyle(.label).foregroundStyle(Theme.muted)
      }
      HStack(alignment: .bottom, spacing: 0) {
        ForEach(Array(days.enumerated()), id: \.offset) { index, day in
          column(day, top: top, today: index == days.count - 1)
            .accessibilityIdentifier("\(id).\(index)")
        }
      }
    }
  }

  private func column(_ day: Day, top: Double, today: Bool) -> some View {
    let range = day.kcal.map { FoodRange.text($0, unit: "kcal") } ?? "--"
    let name = day.day.formatted(.dateTime.weekday(.wide))
    return VStack(spacing: Theme.space2xs) {
      VStack(spacing: Theme.space2xs) {
        Spacer(minLength: 0)
        if let kcal = day.kcal {
          RoundedRectangle(cornerRadius: Theme.spaceXs).fill(Theme.dataEnergy)
            .opacity(today ? 1 : 0.4)
            .frame(height: max(Theme.spaceXs, (kcal.high - kcal.low) / top * Theme.sizeChart))
          Color.clear.frame(height: kcal.low / top * Theme.sizeChart)
        } else {
          Text("--")
          RoundedRectangle(cornerRadius: Theme.spaceXs)
            .strokeBorder(Theme.track, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(height: Theme.sizeSpark)
        }
      }
      .frame(height: Theme.sizeChart).padding(.horizontal, Theme.spaceMd)
      Text(day.day.formatted(.dateTime.weekday(.narrow)))
        .foregroundStyle(today ? Theme.ink : Theme.muted)
      Text(today ? "so far" : " ")
    }
    .textStyle(.axis).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(name), \(range)\(today ? ", so far" : "")")
  }
}
