import Foundation
import StezuCore
import XCTest

/// The widget's fetch-and-cache helper (D-152). Payloads are synthetic.
final class CachedPayloadTests: XCTestCase {
  struct Sample: Decodable, Sendable, Equatable {
    var word: String?
  }

  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("cached-payload-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func reply(_ json: String, status: Int = 200) -> VMResponse {
    VMResponse(status: status, body: Data(json.utf8))
  }

  func testLiveReplyIsReturnedAndCached() async throws {
    let fake = FakeVMTransport(routes: ["GET /surface/today": reply(#"{"word": "alpha"}"#)])
    let fetcher = CachedPayloadFetcher(transport: fake, cache: PayloadCache(directory: directory))

    let result = await fetcher.fetch(Sample.self, path: "/surface/today")

    XCTAssertEqual(result?.value, Sample(word: "alpha"))
    XCTAssertEqual(result?.isCached, false)
    let file = directory.appendingPathComponent("surface_today.json")
    XCTAssertEqual(try Data(contentsOf: file), Data(#"{"word": "alpha"}"#.utf8))
    let sent = await fake.sent
    XCTAssertEqual(sent.map(\.route), ["GET /surface/today"])
  }

  func testOfflineReturnsLastGoodPayload() async throws {
    let fake = FakeVMTransport(routes: ["GET /surface/today": reply(#"{"word": "alpha"}"#)])
    let fetcher = CachedPayloadFetcher(transport: fake, cache: PayloadCache(directory: directory))
    _ = await fetcher.fetch(Sample.self, path: "/surface/today")

    await fake.setOffline(true)
    let result = await fetcher.fetch(Sample.self, path: "/surface/today")

    XCTAssertEqual(result?.value, Sample(word: "alpha"))
    XCTAssertEqual(result?.isCached, true)
  }

  func testRejectedOrBrokenReplyKeepsTheCachedCopy() async throws {
    let fake = FakeVMTransport(routes: ["GET /surface/today": reply(#"{"word": "alpha"}"#)])
    let fetcher = CachedPayloadFetcher(transport: fake, cache: PayloadCache(directory: directory))
    _ = await fetcher.fetch(Sample.self, path: "/surface/today")

    await fake.setResponse(reply(#"{"detail": "no"}"#, status: 401), for: "GET /surface/today")
    let rejected = await fetcher.fetch(Sample.self, path: "/surface/today")
    await fake.setResponse(reply("not json"), for: "GET /surface/today")
    let broken = await fetcher.fetch(Sample.self, path: "/surface/today")

    XCTAssertEqual(rejected?.value, Sample(word: "alpha"))
    XCTAssertEqual(rejected?.isCached, true)
    XCTAssertEqual(broken?.value, Sample(word: "alpha"))
    let file = directory.appendingPathComponent("surface_today.json")
    XCTAssertEqual(try Data(contentsOf: file), Data(#"{"word": "alpha"}"#.utf8))
  }

  func testNothingCachedAndNoServerIsNil() async {
    let fetcher = CachedPayloadFetcher(
      transport: UnconfiguredVMTransport(), cache: PayloadCache(directory: directory))

    let result = await fetcher.fetch(Sample.self, path: "/surface/today")

    XCTAssertNil(result)
  }

  func testEachPathHasItsOwnFile() {
    let cache = PayloadCache(directory: directory)

    XCTAssertEqual(cache.fileURL(for: "/surface/today").lastPathComponent, "surface_today.json")
    XCTAssertEqual(cache.fileURL(for: "/sync/status").lastPathComponent, "sync_status.json")
    XCTAssertEqual(cache.fileURL(for: "/").lastPathComponent, "root.json")
  }
}
