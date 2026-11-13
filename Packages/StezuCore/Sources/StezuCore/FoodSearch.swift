import Foundation

/// The result groups GET /search answers with (server/README.md).
public enum FoodSearchSource: String, Sendable, Equatable {
  /// His own logged foods and recipes that match (D-158); the server puts it first.
  case history
  case dining
  case openFoodFacts = "open_food_facts"
  case usdaFdc = "usda_fdc"
  case estimate
}

/// One group; `status` is the server's ("ok", "error", "skipped", "available"). Each result is
/// already an item at 1 serving, ready for the item list. Groups and results keep the server's
/// order, which is its relevance ranking: nothing here sorts.
public struct FoodSearchGroup: Sendable, Equatable {
  public let source: FoodSearchSource
  /// The server's heading for the group, when it sends one ("Your foods").
  public let title: String?
  public let status: String
  public let results: [FoodSearchResult]

  public init(
    source: FoodSearchSource, title: String? = nil, status: String, results: [FoodSearchResult]
  ) {
    self.source = source
    self.title = title
    self.status = status
    self.results = results
  }

  public var items: [MatchedItem] { results.map(\.item) }

  /// Whether the results list shows this group: not the estimate (it has its own button), not a
  /// skipped source, and not an empty history group (no own foods match, so it says nothing).
  public var isListed: Bool {
    guard source != .estimate, status != "skipped" else { return false }
    return source != .history || status == "error" || !results.isEmpty
  }
}

/// One search result: the item it logs, plus what only the results list shows.
public struct FoodSearchResult: Sendable, Equatable {
  public let item: MatchedItem
  /// The package as labelled ("600 g"), so look-alike products can be told apart; nil if unknown.
  public let packageSize: String?
  /// The serving is the server's 100 g (or mL) stand-in, not one the product names.
  public let servingIsPer100: Bool

  public init(item: MatchedItem, packageSize: String? = nil, servingIsPer100: Bool = false) {
    self.item = item
    self.packageSize = packageSize
    self.servingIsPer100 = servingIsPer100
  }

  /// "North Hall, South Hall · 4 oz", "Example Brand · 600 g" or "Example Brand · 1 cup"; "--"
  /// with nothing to show. With a package size the serving shows only when it says something
  /// more: never the 100 g stand-in, never the package size twice.
  public var detail: String {
    let place = item.halls.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") } ?? item.brand
    var serving = item.serving
    if let size = packageSize, servingIsPer100 || Self.same(serving, size) {
      serving = nil
    }
    let parts = [place, packageSize, serving].compactMap { $0 }.filter { !$0.isEmpty }
    return parts.isEmpty ? "--" : parts.joined(separator: " · ")
  }

  /// "600 g" and "600g" are the same label.
  private static func same(_ a: String?, _ b: String) -> Bool {
    func key(_ text: String) -> String { text.lowercased().filter { !$0.isWhitespace } }
    return a.map { key($0) == key(b) } ?? false
  }
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

  /// Unknown sources are dropped; a result without a name is skipped. Order is kept as sent.
  public static func decode(_ body: Data) throws -> [FoodSearchGroup] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Reply.self, from: body).groups.compactMap { group in
      FoodSearchSource(rawValue: group.source).map {
        FoodSearchGroup(
          source: $0, title: group.title, status: group.status,
          results: group.results.compactMap(\.result))
      }
    }
  }

  private struct Reply: Decodable {
    let groups: [Group]
  }

  private struct Group: Decodable {
    let source: String
    let title: String?
    let status: String
    let results: [Result]
  }

  /// One result of any source. Dining and packaged results carry one number per serving, which
  /// becomes a range here; an estimate already carries ranges. Fields decode leniently.
  /// GET /barcode's found reply has the same shape (BarcodeClient).
  /// Older servers send no `package_size` or `basis`; both are then absent.
  struct Result: Decodable {
    let item: MatchedItem?
    var packageSize: String?
    var servingIsPer100 = false

    var result: FoodSearchResult? {
      item.map {
        FoodSearchResult(item: $0, packageSize: packageSize, servingIsPer100: servingIsPer100)
      }
    }

    enum Keys: String, CodingKey {
      case id, gtin, fdcId, name, brand, hall, halls, serving, portion, label, rough, kcal
      case proteinG, perServing, packageSize, basis
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
      let size: String? = value(.packageSize)
      packageSize = size.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap {
        $0.isEmpty ? nil : $0
      }
      let basis: String? = portion.flatMap { value(.basis, in: $0) }
      servingIsPer100 = label != nil && basis == "per_100"
    }
  }
}
