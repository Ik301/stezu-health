import Foundation

/// One of Stezu's own records for POST /sync (server/README.md): `(kind, id)` is the key and the
/// newest `updatedAt` wins, so every edit is sent with a fresh time. A tombstone has no payload.
public struct SyncRecord: Codable, Sendable, Equatable {
  public var kind, id, updatedAt: String
  public var deleted: Bool
  /// The meal as logged (S-029); nil only for a tombstone. Other kinds add their payloads here.
  public var payload: MealRecord?
  /// A `set` record's payload (S-030); nil for other kinds and tombstones.
  public var setPayload: SetRecord? = nil
  /// A `workout_session` record's payload (S-030).
  public var sessionPayload: SessionRecord? = nil

  enum CodingKeys: String, CodingKey {
    case kind, id, deleted, payload
    case updatedAt = "updated_at"
  }

  /// A logged or edited meal, stamped `at` to the millisecond so an edit is always newer.
  public static func meal(
    _ meal: LoggedMeal, edited: Bool, at date: Date, calendar: Calendar = .current
  ) -> SyncRecord {
    SyncRecord(
      kind: "meal", id: meal.id.uuidString, updatedAt: stamp(date, calendar), deleted: false,
      payload: MealRecord(meal, edited: edited, calendar: calendar))
  }

  /// A deleted or undone meal.
  public static func deletedMeal(_ id: UUID, at date: Date, calendar: Calendar = .current)
    -> SyncRecord
  {
    SyncRecord(
      kind: "meal", id: id.uuidString, updatedAt: stamp(date, calendar), deleted: true,
      payload: nil)
  }

  static func stamp(_ date: Date, _ calendar: Calendar) -> String {
    ISO8601DateFormatter.string(
      from: date, timeZone: calendar.timeZone,
      formatOptions: [.withInternetDateTime, .withFractionalSeconds])
  }
}

/// One `payload` key for every kind: the kind picks the type it decodes as.
extension SyncRecord {
  public init(from decoder: any Decoder) throws {
    let box = try decoder.container(keyedBy: CodingKeys.self)
    kind = try box.decode(String.self, forKey: .kind)
    id = try box.decode(String.self, forKey: .id)
    updatedAt = try box.decode(String.self, forKey: .updatedAt)
    deleted = try box.decode(Bool.self, forKey: .deleted)
    switch kind {
    case "set": setPayload = try box.decodeIfPresent(SetRecord.self, forKey: .payload)
    case "workout_session":
      sessionPayload = try box.decodeIfPresent(SessionRecord.self, forKey: .payload)
    default: payload = try box.decodeIfPresent(MealRecord.self, forKey: .payload)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var box = encoder.container(keyedBy: CodingKeys.self)
    try box.encode(kind, forKey: .kind)
    try box.encode(id, forKey: .id)
    try box.encode(updatedAt, forKey: .updatedAt)
    try box.encode(deleted, forKey: .deleted)
    try box.encodeIfPresent(setPayload, forKey: .payload)
    try box.encodeIfPresent(sessionPayload, forKey: .payload)
    try box.encodeIfPresent(payload, forKey: .payload)
  }
}

/// A meal's payload: when it was eaten, its day, the confirm state and each item with its ranges
/// and source. No photo: the server already has the photos it scanned.
public struct MealRecord: Codable, Sendable, Equatable {
  public struct Item: Codable, Sendable, Equatable {
    public let itemId, name: String
    /// The hall serving it, the brand, or "estimate" for a rough item; nil when unknown.
    public let source: String?
    public let halls: [String]?
    public let serving: String?
    public let servings, confidence: Double?
    public let rough: Bool
    /// Nil when the item has no range, never 0.
    public let kcal, proteinG: FoodRange?

    enum CodingKeys: String, CodingKey {
      case name, source, halls, serving, servings, confidence, rough, kcal
      case itemId = "item_id"
      case proteinG = "protein_g"
    }

    init(_ item: MatchedItem) {
      (itemId, name, halls, serving) = (item.itemId, item.name, item.halls, item.serving)
      source = item.hall ?? item.brand ?? (item.isRough ? "estimate" : nil)
      (servings, confidence, rough) = (item.servings, item.confidence, item.isRough)
      (kcal, proteinG) = (item.kcal, item.proteinG)
    }
  }

  public let id, eatenAt, day, status: String
  /// True once the meal was changed after Log (S-019).
  public let edited: Bool
  /// Whether Health took the meal; nil until the write was tried.
  public let inHealth: Bool?
  public let items: [Item]

  enum CodingKeys: String, CodingKey {
    case id, day, status, edited, items
    case eatenAt = "eaten_at"
    case inHealth = "in_health"
  }

  public init(_ meal: LoggedMeal, edited: Bool, calendar: Calendar = .current) {
    id = meal.id.uuidString
    eatenAt = ISO8601DateFormatter.string(
      from: meal.loggedAt, timeZone: calendar.timeZone, formatOptions: .withInternetDateTime)
    let parts = calendar.dateComponents([.year, .month, .day], from: meal.loggedAt)
    day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    (status, self.edited, inHealth) = (meal.status.rawValue, edited, meal.inHealth)
    items = meal.items.map(Item.init)
  }
}
