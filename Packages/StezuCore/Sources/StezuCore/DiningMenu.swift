import Foundation

/// One dining hall's menu for one service day, as served by the VM endpoint.
/// The endpoint scrapes FoodPro; this type mirrors its JSON, not FoodPro's HTML.
public struct DiningMenu: Codable, Sendable, Equatable {
  /// Hall identifier as the endpoint names it, such as "example-hall".
  public let hall: String
  /// Service day in the hall's local calendar, "yyyy-MM-dd". Kept as text so
  /// decoding never shifts the day across time zones.
  public let date: String
  public let meals: [DiningMeal]

  public init(hall: String, date: String, meals: [DiningMeal]) {
    self.hall = hall
    self.date = date
    self.meals = meals
  }

  /// True when no meal lists any item. Such a menu is treated as unavailable.
  public var hasNoItems: Bool { meals.allSatisfy { $0.items.isEmpty } }
}

/// A meal period, such as breakfast, lunch or dinner.
public struct DiningMeal: Codable, Sendable, Equatable {
  public let name: String
  public let items: [DiningMenuItem]

  public init(name: String, items: [DiningMenuItem]) {
    self.name = name
    self.items = items
  }
}

/// One dish. Nutrition fields are per serving and nil when FoodPro does not
/// publish them; nil is never read as 0.
public struct DiningMenuItem: Codable, Sendable, Equatable {
  public let name: String
  public let station: String?
  public let servingSize: String?
  public let calories: Double?
  public let proteinGrams: Double?
  public let carbohydrateGrams: Double?
  public let fatGrams: Double?

  public init(
    name: String, station: String? = nil, servingSize: String? = nil,
    calories: Double? = nil, proteinGrams: Double? = nil,
    carbohydrateGrams: Double? = nil, fatGrams: Double? = nil
  ) {
    self.name = name
    self.station = station
    self.servingSize = servingSize
    self.calories = calories
    self.proteinGrams = proteinGrams
    self.carbohydrateGrams = carbohydrateGrams
    self.fatGrams = fatGrams
  }
}

/// The answer for one hall and day: a menu with items, or an explicit absent
/// state with a reason. There is no "empty menu" value.
public enum DiningMenuResult: Sendable, Equatable {
  case available(DiningMenu)
  case unavailable(reason: String)

  /// The menu, or nil when unavailable.
  public var menu: DiningMenu? {
    if case .available(let menu) = self { return menu }
    return nil
  }
}

/// What the client asks for. The transport turns this into a real request;
/// the endpoint URL and token live with the transport, not in core.
public struct DiningMenuRequest: Sendable, Equatable {
  public let hall: String
  public let date: String

  public init(hall: String, date: String) {
    self.hall = hall
    self.date = date
  }
}

/// A raw reply from the transport: an HTTP-style status code and the body.
public struct DiningTransportResponse: Sendable, Equatable {
  public let statusCode: Int
  public let body: Data

  public init(statusCode: Int, body: Data) {
    self.statusCode = statusCode
    self.body = body
  }
}

/// Moves a request to the VM endpoint and back. The app supplies the real one;
/// tests supply a fake, so core imports no networking.
public protocol DiningMenuTransport: Sendable {
  func send(_ request: DiningMenuRequest) async throws -> DiningTransportResponse
}

public enum DiningMenuError: Error, Sendable, Equatable {
  /// A status other than 200 or 404.
  case unexpectedStatus(Int)
  /// The body did not match the endpoint's JSON shape.
  case malformedBody
}

/// Fetches and decodes menus through an injected transport.
public struct DiningMenuClient: Sendable {
  private let transport: any DiningMenuTransport

  public init(transport: any DiningMenuTransport) {
    self.transport = transport
  }

  /// 404, `"status": "unavailable"` and a menu without items all map to
  /// `.unavailable`. Other statuses and bad JSON throw.
  public func menu(hall: String, date: String) async throws -> DiningMenuResult {
    let response = try await transport.send(DiningMenuRequest(hall: hall, date: date))
    switch response.statusCode {
    case 200: return try Self.decode(response.body)
    case 404: return .unavailable(reason: "no menu published for \(hall) on \(date)")
    default: throw DiningMenuError.unexpectedStatus(response.statusCode)
    }
  }

  /// Decodes the endpoint envelope:
  /// `{"status": "available", "menu": {...}}` or
  /// `{"status": "unavailable", "reason": "..."}`.
  public static func decode(_ body: Data) throws -> DiningMenuResult {
    let envelope: Envelope
    do {
      envelope = try JSONDecoder().decode(Envelope.self, from: body)
    } catch {
      throw DiningMenuError.malformedBody
    }
    switch envelope.status {
    case "available":
      guard let menu = envelope.menu else { throw DiningMenuError.malformedBody }
      if menu.hasNoItems {
        return .unavailable(reason: "menu for \(menu.hall) on \(menu.date) lists no items")
      }
      return .available(menu)
    case "unavailable":
      return .unavailable(reason: envelope.reason ?? "menu unavailable")
    default:
      throw DiningMenuError.malformedBody
    }
  }

  private struct Envelope: Decodable {
    let status: String
    let menu: DiningMenu?
    let reason: String?
  }
}
