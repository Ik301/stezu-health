import Foundation

/// The last good reply from each server path, one JSON file per path, so a home-screen widget
/// can still show something offline (D-152). The widget keeps it in its own container; the app
/// never reads it.
public struct PayloadCache: Sendable {
  public let directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  /// "/surface/today" is kept in surface_today.json.
  public func fileURL(for path: String) -> URL {
    let name = path.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "_")
    return directory.appendingPathComponent((name.isEmpty ? "root" : name) + ".json")
  }

  public func load(path: String) -> Data? {
    try? Data(contentsOf: fileURL(for: path))
  }

  public func save(_ data: Data, path: String) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try data.write(to: fileURL(for: path), options: .atomic)
  }
}

/// A payload, and whether it came from the cache because the server didn't answer with one.
public struct Fetched<Value: Sendable>: Sendable {
  public var value: Value
  public var isCached: Bool
}

/// GET one path with the saved server address and token, and fall back to the last good reply.
public struct CachedPayloadFetcher: Sendable {
  public let transport: any VMTransport
  public let cache: PayloadCache

  public init(transport: any VMTransport, cache: PayloadCache) {
    self.transport = transport
    self.cache = cache
  }

  /// A 200 whose body decodes as `type` replaces the cached copy and is returned. Anything else
  /// (no server set, offline, 401, a body that doesn't decode) returns the cached copy, or nil
  /// when there is none; the widget shows nil as "--".
  public func fetch<Value: Decodable & Sendable>(_ type: Value.Type, path: String) async
    -> Fetched<Value>?
  {
    if let reply = try? await transport.send(VMRequest(path: path)), reply.status == 200,
      let value = try? JSONDecoder().decode(type, from: reply.body)
    {
      try? cache.save(reply.body, path: path)
      return Fetched(value: value, isCached: false)
    }
    guard let data = cache.load(path: path), let value = try? JSONDecoder().decode(type, from: data)
    else { return nil }
    return Fetched(value: value, isCached: true)
  }
}
