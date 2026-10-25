import CryptoKit
import StezuCore
import SwiftUI
import UIKit

/// Where a captured meal is in matching (S-013).
enum MatchState: Sendable, Equatable {
  case matching
  case matched(PhotoMatch)
  case failed
}

/// Sends a saved meal photo to POST /scan: downscaled to about 1000 px, hashed, with the meal's
/// id, the service day and the meal period from the capture time.
struct MealMatcher: Sendable {
  let environment: AppEnvironment

  func match(_ meal: CapturedMeal) async -> MatchState {
    guard let photo = await environment.mealCaptures.photo(for: meal.id),
      let jpeg = await Self.downscaled(photo)
    else { return .failed }
    let day = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
    let hash = SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined()
    let match = try? await PhotoMatchClient(transport: environment.vmTransport).scan(
      mealID: meal.id, date: day.format(meal.capturedAt),
      meal: MealPeriod.at(meal.capturedAt), jpeg: jpeg, sha256: hash)
    return match.map { .matched($0) } ?? .failed
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

  var body: some View {
    switch state {
    case .matching:
      status("Matching...", id: "food.matching", detail: "Photo saved on this phone.")
    case .failed:
      status("Could not match", id: "food.match.failed", detail: "Photo saved on this phone.")
    case .matched(let match):
      matched(match)
    }
  }

  private func status(_ title: String, id: String, detail: String) -> some View {
    VStack(spacing: 12) {
      Text(title).font(.system(size: Theme.subtitleSize, weight: .semibold))
        .foregroundStyle(Theme.text).accessibilityIdentifier(id)
      Text(detail).font(.system(size: Theme.labelSize))
        .foregroundStyle(Theme.label).accessibilityIdentifier("food.captured.saved")
    }
    .presentationDetents([.fraction(0.3)])
  }

  private func matched(_ match: PhotoMatch) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text("Meal").font(.system(size: Theme.subtitleSize, weight: .semibold))
            .accessibilityIdentifier("food.match.title")
          Spacer()
          Text(Self.range(match.totalKcal, unit: "kcal"))
            .accessibilityIdentifier("food.match.total.kcal")
          Text(Self.range(match.totalProteinG, unit: "g protein"))
            .accessibilityIdentifier("food.match.total.protein")
        }
        ForEach(Array(match.items.enumerated()), id: \.offset) { index, item in
          row(item, id: "food.match.item.\(index)")
        }
      }
      .padding(16)
    }
    .background(Theme.background)
    .presentationDetents([.medium, .large])
  }

  private func row(_ item: MatchedItem, id: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(item.name).font(.system(size: Theme.subtitleSize, weight: .medium))
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
        Text(item.hall ?? (item.isRough ? "Not on a menu" : "--"))
          .accessibilityIdentifier("\(id).hall")
        Text(Self.servings(item)).accessibilityIdentifier("\(id).servings")
        Spacer()
        Text(Self.range(item.proteinG, unit: "g protein"))
          .accessibilityIdentifier("\(id).protein")
      }
      .font(.system(size: Theme.labelSize)).foregroundStyle(Theme.label)
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
