import CryptoKit
import StezuCore
import SwiftUI
import UIKit

/// Where a captured meal is in matching (S-013).
enum MatchState: Sendable, Equatable {
  case matching
  case matched(PhotoMatch)
  /// No connection or no server set: the meal waits in the queue (S-017).
  case pending
  case failed
}

/// Sends a saved meal photo to POST /scan: downscaled to about 1000 px, hashed, with the meal's
/// id, the service day and the meal period from the capture time.
struct MealMatcher: Sendable {
  let environment: AppEnvironment

  func match(_ meal: CapturedMeal) async -> MatchState {
    do {
      return .matched(try await scan(meal))
    } catch is VMTransportError {
      return .pending
    } catch {
      return .failed
    }
  }

  /// Sends the saved photo and keeps the reply with the meal, so a relaunch finds it matched.
  func scan(_ meal: CapturedMeal) async throws -> PhotoMatch {
    guard let photo = await environment.mealCaptures.photo(for: meal.id),
      let jpeg = await Self.downscaled(photo)
    else { throw CocoaError(.fileReadNoSuchFile) }
    let day = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
    let hash = SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined()
    let reply = try await PhotoMatchClient(transport: environment.vmTransport).scanReply(
      mealID: meal.id, date: day.format(meal.capturedAt),
      meal: MealPeriod.at(meal.capturedAt), jpeg: jpeg, sha256: hash)
    let match = try PhotoMatchClient.decode(reply)
    try await environment.mealCaptures.saveReply(reply, for: meal.id)
    return match
  }

  /// Retries the saved meals still pending, oldest first, and returns the newest one matched now.
  func retryQueue() async -> QueuedMeal? {
    var queue = await environment.mealCaptures.queue()
    let matched = await queue.retry {
      try await scan(CapturedMeal(id: $0.id, capturedAt: $0.capturedAt))
    }
    return queue.meals.last { matched.contains($0.id) }
  }

  @MainActor static func downscaled(_ photo: Data, maxSide: CGFloat = 1000) -> Data? {
    guard let image = UIImage(data: photo) else { return nil }
    let scale = min(1, maxSide / max(image.size.width, image.size.height))
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).jpegData(
      withCompressionQuality: 0.8
    ) { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
  }
}

/// The sheet after the shutter: "Matching...", then the matched items with ranges and the totals.
struct PhotoMatchSheet: View {
  let state: MatchState
  /// Today's line while a meal is pending, such as "-- kcal, +1 pending".
  var today: String?
  /// The Log tap with the edited items.
  var log: ([MatchedItem]) -> Void = { _ in }

  var body: some View {
    switch state {
    case .matching:
      status("Matching...", id: "food.matching", detail: "Photo saved on this phone.")
    case .pending:
      status(
        "Pending, will match when online", id: "food.match.pending",
        detail: "Photo saved on this phone.")
    case .failed:
      status("Could not match", id: "food.match.failed", detail: "Photo saved on this phone.")
    case .matched(let match):
      MealEditor(match: match, log: log)
    }
  }

  private func status(_ title: String, id: String, detail: String) -> some View {
    VStack(spacing: 12) {
      Text(title).font(.system(size: Theme.subtitleSize, weight: .semibold))
        .foregroundStyle(Theme.text).accessibilityIdentifier(id)
      Text(detail).font(.system(size: Theme.labelSize))
        .foregroundStyle(Theme.label).accessibilityIdentifier("food.captured.saved")
      if let today {
        Text("Today: \(today)").font(.system(size: Theme.labelSize, weight: .medium))
          .foregroundStyle(Theme.text).accessibilityIdentifier("food.today")
      }
    }
    .presentationDetents([.fraction(0.3)])
  }

  /// One item: a tap on the name opens search to replace it (S-015); `controls` go below.
  static func row<Controls: View>(
    _ item: MatchedItem, id: String, onName: @escaping () -> Void,
    @ViewBuilder controls: () -> Controls
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(item.name).font(.system(size: Theme.subtitleSize, weight: .medium))
          .onTapGesture(perform: onName).accessibilityAddTraits(.isButton)
          .accessibilityIdentifier("\(id).name")
        if item.isRough {
          Text("rough").font(.system(size: Theme.labelSize, weight: .semibold))
            .foregroundStyle(Theme.invertedText).padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(Theme.invertedCard))
            .accessibilityIdentifier("\(id).rough")
        }
        Spacer()
        Text(Self.range(item.kcal, unit: "kcal")).accessibilityIdentifier("\(id).kcal")
      }
      HStack {
        Text(item.hall ?? item.brand ?? (item.isRough ? "Not on a menu" : "--"))
          .accessibilityIdentifier("\(id).hall")
        Text(Self.servings(item)).accessibilityIdentifier("\(id).servings")
        Spacer()
        Text(Self.range(item.proteinG, unit: "g protein"))
          .accessibilityIdentifier("\(id).protein")
      }
      .font(.system(size: Theme.labelSize)).foregroundStyle(Theme.label)
      controls()
    }
    .foregroundStyle(Theme.text)
    .padding(12)
    .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.card))
    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.cardBorder))
  }

  /// "200-260 kcal", or "--" when the range is unknown. Never a single number.
  static func range(_ range: FoodRange?, unit: String) -> String {
    guard let range else { return "-- \(unit)" }
    return "\(Int(range.low.rounded()))-\(Int(range.high.rounded())) \(unit)"
  }

  /// "1.5 x 4 oz", "1 x serving", or "--".
  static func servings(_ item: MatchedItem) -> String {
    guard let count = item.servings else { return "--" }
    let number = count.formatted(.number.precision(.fractionLength(0...1)))
    return "\(number) x \(item.serving ?? "serving")"
  }
}
