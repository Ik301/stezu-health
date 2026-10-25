import Foundation

/// The meal period sent to POST /scan. The server also matches brunch for breakfast and lunch.
public enum MealPeriod: String, Sendable, Equatable {
  case breakfast, lunch, dinner

  /// Breakfast before 10:30, lunch before 16:00, dinner after, in the given calendar.
  public static func at(_ date: Date, calendar: Calendar = .current) -> MealPeriod {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    if minutes < 10 * 60 + 30 { return .breakfast }
    return minutes < 16 * 60 ? .lunch : .dinner
  }
}

/// One item the server found in the photo (server/README.md). Ranges are for `servings` of
/// `serving`; a range with a null end is nil (unknown), never 0.
public struct MatchedItem: Sendable, Equatable, Decodable {
  public let itemId: String
  public let name: String
  /// The first hall serving it; nil for an item on no menu.
  public let hall: String?
  public let halls: [String]?
  public let serving: String?
  public let servings: Double?
  /// The server's confidence in the match, 0 to 1.
  public let confidence: Double?
  public let rough: Bool?
  public let kcal: FoodRange?
  public let proteinG: FoodRange?

  public static let unlistedID = "unlisted"

  /// A rough estimate: the item is on no menu, or the server said so.
  public var isRough: Bool { rough == true || itemId == Self.unlistedID }
}

extension KeyedDecodingContainer {
  /// Optional ranges decode leniently: a range with a null or missing end is nil.
  public func decodeIfPresent(_ type: FoodRange.Type, forKey key: Key) throws -> FoodRange? {
    try? decode(FoodRange.self, forKey: key)
  }
}

/// The server's answer for one photo. Totals are summed here, so edits can recompute them.
public struct PhotoMatch: Sendable, Equatable, Decodable {
  public let mealId: String
  public let items: [MatchedItem]

  public var totalKcal: FoodRange? { FoodRange.total(items.map(\.kcal)) }
  public var totalProteinG: FoodRange? { FoodRange.total(items.map(\.proteinG)) }
}

public enum PhotoMatchError: Error, Sendable, Equatable {
  case unexpectedStatus(Int)
}

/// Sends one photo to POST /scan in dining mode and decodes the matched items.
public struct PhotoMatchClient: Sendable {
  private let transport: any VMTransport

  public init(transport: any VMTransport) {
    self.transport = transport
  }

  /// `jpeg` is the downscaled photo, `sha256` its lowercase hex hash, `date` "yyyy-MM-dd".
  public func scan(
    mealID: UUID, date: String, meal: MealPeriod, jpeg: Data, sha256: String
  ) async throws -> PhotoMatch {
    let fields = [
      "meal_id": mealID.uuidString.lowercased(), "date": date, "meal": meal.rawValue,
      "mode": "dining", "image_base64": jpeg.base64EncodedString(), "photo_sha256": sha256,
    ]
    let body = try JSONSerialization.data(withJSONObject: fields, options: .sortedKeys)
    let response = try await transport.send(
      VMRequest(method: "POST", path: "/scan", body: body, contentType: "application/json"))
    guard response.status == 200 else { throw PhotoMatchError.unexpectedStatus(response.status) }
    return try Self.decode(response.body)
  }

  public static func decode(_ body: Data) throws -> PhotoMatch {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(PhotoMatch.self, from: body)
  }
}
