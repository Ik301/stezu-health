import Foundation

/// One HealthKit sample as POST /sync takes it (server/README.md); the UUID is the dedupe key.
public struct SyncSample: Codable, Sendable, Equatable {
  public var uuid, type, start, end: String
  /// The value in `unit`, or a category's raw value; nil only for workouts, never 0 for absent.
  public var value: Double?
  public var unit, sourceName, sourceBundle: String?
  public var metadata: [String: Double]?

  enum CodingKeys: String, CodingKey {
    case uuid, type, start, end, value, unit, metadata
    case sourceName = "source_name"
    case sourceBundle = "source_bundle"
  }

  public init(
    uuid: String, type: String, start: String, end: String, value: Double?, unit: String?,
    sourceName: String?, sourceBundle: String?, metadata: [String: Double]? = nil
  ) {
    (self.uuid, self.type, self.start, self.end, self.value, self.unit) =
      (uuid, type, start, end, value, unit)
    (self.sourceName, self.sourceBundle, self.metadata) = (sourceName, sourceBundle, metadata)
  }

  /// ISO 8601 with the device's offset, as /sync requires.
  public static func timestamp(_ date: Date) -> String {
    ISO8601DateFormatter.string(
      from: date, timeZone: .current, formatOptions: .withInternetDateTime)
  }
}

/// A sample removed from Health (`HKDeletedObject`).
public struct SyncDeletion: Codable, Sendable, Equatable {
  public var uuid: String
  public var type: String?

  public init(uuid: String, type: String?) { (self.uuid, self.type) = (uuid, type) }
}

/// One POST /sync body. A retry resends it unchanged, so the server sees the same `batchID`.
public struct SyncBatch: Codable, Sendable, Equatable {
  public var deviceID, batchID: String
  public var samples: [SyncSample]
  public var deleted: [SyncDeletion]

  enum CodingKeys: String, CodingKey {
    case samples, deleted
    case deviceID = "device_id"
    case batchID = "batch_id"
  }
}

/// Saved after every change: device id, an anchor per type, unaccepted batches, last status.
public struct SyncState: Codable, Sendable, Equatable {
  public var deviceID: String
  public var anchors: [String: Data] = [:]
  public var pending: [SyncBatch] = []
  /// Nil before the first full sync, never 0.
  public var lastSyncAt: Date?
  public var samplesTotal: Int?

  public init(deviceID: String = UUID().uuidString) { self.deviceID = deviceID }
}

/// Reads each type in pages from its anchor; a page is queued and saved with its new anchor
/// before it is sent, and leaves the queue only on a 2xx. A failure ends the run, queue kept.
public actor HealthSync {
  public static let batchSize = 2000
  public static let backfillDays = 90
  public private(set) var state: SyncState
  private let save: @Sendable (SyncState) -> Void
  private var running = false

  public init(state: SyncState, save: @escaping @Sendable (SyncState) -> Void = { _ in }) {
    (self.state, self.save) = (state, save)
  }

  /// The queue, each type (none if `health` is nil), then GET /sync/status. Never two at once.
  @discardableResult
  public func run(health: (any HealthStore)?, transport: any VMTransport, now: Date = Date())
    async -> SyncState
  {
    guard !running else { return state }
    running = true
    defer { running = false }
    guard await flush(transport) else { return state }
    let since = now.addingTimeInterval(-Double(Self.backfillDays) * 86_400)
    for type in HealthType.allCases {
      while let page = try? await health?.changes(
        of: type, after: state.anchors[type.rawValue], since: since, limit: Self.batchSize),
        !(page.samples.isEmpty && page.deleted.isEmpty)
      {
        state.pending.append(
          SyncBatch(
            deviceID: state.deviceID, batchID: UUID().uuidString, samples: page.samples,
            deleted: page.deleted))
        state.anchors[type.rawValue] = page.anchor
        save(state)
        guard await flush(transport) else { return state }
      }
    }
    if let reply = try? await transport.send(VMRequest(path: "/sync/status")), reply.status == 200 {
      let server = try? JSONSerialization.jsonObject(with: reply.body) as? [String: Any]
      state.samplesTotal = server?["samples_total"] as? Int
      state.lastSyncAt = now  // only once the server answered, never for an unconfigured app
    }
    save(state)
    return state
  }

  /// Sends the queue in order; false at the first failure (offline, not configured, non-2xx).
  private func flush(_ transport: any VMTransport) async -> Bool {
    while let batch = state.pending.first {
      guard let body = try? JSONEncoder().encode(batch),
        let reply = try? await transport.send(
          VMRequest(method: "POST", path: "/sync", body: body, contentType: "application/json")),
        (200..<300).contains(reply.status)
      else { return false }
      state.pending.removeFirst()
      save(state)
    }
    return true
  }
}
