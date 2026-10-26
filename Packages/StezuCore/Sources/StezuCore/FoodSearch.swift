import Foundation

/// The result groups GET /search answers with (server/README.md).
public enum FoodSearchSource: String, Sendable, Equatable {
  case dining
  case openFoodFacts = "open_food_facts"
  case usdaFdc = "usda_fdc"
  case estimate
}

/// One group; `status` is the server's ("ok", "error", "skipped", "available"). Each result is
/// already an item at 1 serving, ready for the item list.
public struct FoodSearchGroup: Sendable, Equatable {
  public let source: FoodSearchSource
  public let status: String
  public let items: [MatchedItem]
}

/// GET /search for typed text, and the same call with estimate=true for a rough text estimate.
public struct FoodSearchClient: Sendable {
  /// A picked result is one known value per serving; the portion eaten is what is unsure, so it
  /// gets the no-depth photo spread at full confidence (D-037): plus or minus 25%.
  public static let pickSpread = 0.25
  private let transport: any VMTransport

  public init(transport: any VMTransport) {
    self.transport = transport
  }

  /// `date` is "yyyy-MM-dd"; `meal` narrows the dining items to that period.
  public func search(_ text: String, date: String, meal: MealPeriod?) async throws
    -> [FoodSearchGroup]
  {
    try await get(["q": text, "date": date, "meal": meal?.rawValue].compactMapValues { $0 })
  }

  /// The model's rough estimate for the text, or nil when the server could not make one.
  public func estimate(_ text: String, date: String) async throws -> MatchedItem? {
    let groups = try await get(["q": text, "date": date, "estimate": "true"])
    return groups.first { $0.source == .estimate }?.items.first
  }

  private func get(_ query: [String: String]) async throws -> [FoodSearchGroup] {
    let response = try await transport.send(VMRequest(path: "/search", query: query))
    guard response.status == 200 else { throw PhotoMatchError.unexpectedStatus(response.status) }
    return try Self.decode(response.body)
  }

  /// Unknown sources are dropped; a result without a name is skipped.
  public static func decode(_ body: Data) throws -> [FoodSearchGroup] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Reply.self, from: body).groups.compactMap { group in
      FoodSearchSource(rawValue: group.source).map {
        FoodSearchGroup(source: $0, status: group.status, items: group.results.compactMap(\.item))
      }
    }
  }

  private struct Reply: Decodable {
    let groups: [Group]
  }

  private struct Group: Decodable {
    let source: String
    let status: String
    let results: [Result]
  }

  /// One result of any source. Dining and packaged results carry one number per serving, which
  /// becomes a range here; an estimate already carries ranges. Fields decode leniently.
  /// GET /barcode's found reply has the same shape (BarcodeClient).
  struct Result: Decodable {
    let item: MatchedItem?

    enum Keys: String, CodingKey {
      case id, gtin, fdcId, name, brand, hall, halls, serving, portion, label, rough, kcal
      case proteinG, perServing
    }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: Keys.self)
      let portion = try? c.nestedContainer(keyedBy: Keys.self, forKey: .perServing)
      func value<T: Decodable>(_ key: Keys, in box: KeyedDecodingContainer<Keys>? = nil) -> T? {
        (try? (box ?? c).decodeIfPresent(T.self, forKey: key)) ?? nil
      }
      func amount(_ key: Keys) -> FoodRange? {
        if let range = try? c.decode(FoodRange.self, forKey: key) { return range }
        let point: Double? = portion.flatMap { value(key, in: $0) } ?? value(key)
        return point.map { FoodRange(low: $0 * (1 - pickSpread), high: $0 * (1 + pickSpread)) }
      }
      guard let name: String = value(.name), !name.isEmpty else {
        item = nil
        return
      }
      let fdc: Int? = value(.fdcId)
      let id: String? = value(.id) ?? value(.gtin) ?? fdc.map(String.init)
      let halls: [String]? = value(.halls)
      let hall: String? = value(.hall)
      let label: String? = portion.flatMap { value(.label, in: $0) }
      let serving: String? = value(.serving) ?? value(.portion)
      item = MatchedItem(
        itemId: id ?? name, name: name, hall: halls?.first ?? hall, halls: halls,
        brand: value(.brand), serving: label ?? serving, servings: 1, confidence: nil,
        rough: value(.rough), kcal: amount(.kcal), proteinG: amount(.proteinG))
    }
  }
}
