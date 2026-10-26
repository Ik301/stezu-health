import Foundation

/// What GET /barcode/{gtin} found (server/README.md). An unknown code is its own answer, never an
/// item with empty values.
public enum BarcodeLookup: Sendable, Equatable {
  /// The product at 1 serving, with its serving label and ranges, ready for the item list.
  case found(MatchedItem)
  case notFound(gtin: String)
}

/// Looks a scanned package code up in Open Food Facts through the VM server.
public struct BarcodeClient: Sendable {
  private let transport: any VMTransport

  public init(transport: any VMTransport) {
    self.transport = transport
  }

  /// True for the 8 to 14 digits the server accepts; other payloads are not food codes.
  public static func isGTIN(_ code: String) -> Bool {
    (8...14).contains(code.count) && code.allSatisfy { $0.isASCII && $0.isNumber }
  }

  public func lookup(_ gtin: String) async throws -> BarcodeLookup {
    let response = try await transport.send(VMRequest(path: "/barcode/\(gtin)"))
    guard response.status == 200 else { throw PhotoMatchError.unexpectedStatus(response.status) }
    return try Self.decode(response.body)
  }

  /// A found product decodes like a packaged search result: its per-serving values become ranges
  /// (`FoodSearchClient.pickSpread`). A found reply without a name cannot be shown, so it throws.
  public static func decode(_ body: Data) throws -> BarcodeLookup {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let reply = try decoder.decode(Reply.self, from: body)
    if reply.status == "not_found" { return .notFound(gtin: reply.gtin) }
    guard reply.status == "found", let item = try decoder.decode(Product.self, from: body).item
    else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "unexpected barcode reply \(reply.status)"))
    }
    return .found(item)
  }

  private struct Reply: Decodable {
    let status: String
    let gtin: String
  }

  private typealias Product = FoodSearchClient.Result
}
