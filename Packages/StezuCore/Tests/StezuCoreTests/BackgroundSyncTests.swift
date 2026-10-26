import Foundation
import XCTest

@testable import StezuCore

/// S-033: the background pass is S-028's anchored pass with `background: true`. When iOS ends it
/// (the task is cancelled) it stops at the next step, and nothing queued is lost: a batch leaves
/// the queue only on a 2xx, and an anchor is saved only together with its batch. Synthetic data.
final class BackgroundSyncTests: XCTestCase {
  final class SavedStates: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [SyncState] = []
    var all: [SyncState] { lock.withLock { states } }
    func append(_ state: SyncState) { lock.withLock { states.append(state) } }
  }

  /// Answers like the server, but iOS's expiration arrives during the `expireOn`-th POST /sync:
  /// the running task is cancelled, and that call either fails (`answered` false, as URLSession
  /// throws on cancel) or still gets its 200.
  actor ExpiringTransport: VMTransport {
    private let expireOn: Int
    private let answered: Bool
    private(set) var posts: [SyncBatch] = []

    init(expireOn: Int, answered: Bool) { (self.expireOn, self.answered) = (expireOn, answered) }

    func send(_ request: VMRequest) async throws -> VMResponse {
      guard request.route == "POST /sync" else {
        return VMResponse(status: 200, body: Data(#"{"samples_total": 3}"#.utf8))
      }
      posts.append(try JSONDecoder().decode(SyncBatch.self, from: request.body ?? Data()))
      guard posts.count == expireOn else { return VMResponse(status: 200) }
      withUnsafeCurrentTask { $0?.cancel() }
      if !answered { throw CancellationError() }
      return VMResponse(status: 200)
    }
  }

  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func sample(_ index: Int) -> SyncSample {
    SyncSample(
      uuid: "SAMPLE-\(index)", type: "HKQuantityTypeIdentifierStepCount",
      start: "2027-01-15T08:00:00-05:00", end: "2027-01-15T08:05:00-05:00", value: 10,
      unit: "count", sourceName: "Example Phone", sourceBundle: "com.example.phone")
  }

  private func visit(_ hour: Double) -> SyncRecord {
    var log = LocationLog()
    return log.apply(
      .visit(
        arrival: now + hour * 3600, departure: nil, latitude: 10.25, longitude: -30.5,
        accuracy: 40), at: now)
  }

  func testExpirationLeavesQueueIntact() async throws {
    let health = FakeHealthStore(changes: [.stepCount: [.added(sample(1))]])
    let saved = SavedStates()
    let sync = HealthSync(state: SyncState(deviceID: "DEVICE-1"), save: saved.append)
    await sync.enqueue([visit(1)])
    await sync.enqueue([visit(2)])
    let queued = await sync.state.pending

    // iOS expires the run while the first batch is in flight: both batches stay, same ids, and
    // Health is not read.
    let inFlight = ExpiringTransport(expireOn: 1, answered: false)
    let first = await Task { await sync.run(health: health, transport: inFlight, background: true) }
      .value
    XCTAssertEqual(first.pending, queued, "a batch left the queue without a 2xx")
    XCTAssertTrue(first.anchors.isEmpty, "Health was read after the expiration")
    XCTAssertNil(first.lastBackgroundSyncAt, "an expired run shows as a background sync")
    XCTAssertEqual(saved.all.last, first, "the queue on disk differs")

    // It expires while the server accepts the first batch: that one leaves, the second waits
    // unsent, and the run stops there.
    let accepted = ExpiringTransport(expireOn: 1, answered: true)
    let second = await Task {
      await sync.run(health: health, transport: accepted, background: true)
    }
    .value
    let posted = await accepted.posts
    XCTAssertEqual(posted.map(\.batchID), [queued[0].batchID], "it kept sending after expiring")
    XCTAssertEqual(second.pending, [queued[1]], "the waiting batch was dropped")
    XCTAssertTrue(second.anchors.isEmpty, "Health was read after the expiration")
    XCTAssertNil(second.lastBackgroundSyncAt)
    XCTAssertEqual(saved.all.last, second)

    // The next run sends the rest with the same id, reads Health, and records a background
    // sync, not a foreground one.
    let calm = ExpiringTransport(expireOn: 0, answered: true)
    let third = await sync.run(health: health, transport: calm, now: now, background: true)
    let rest = await calm.posts
    XCTAssertEqual(rest.first?.batchID, queued[1].batchID, "a new id on retry")
    XCTAssertEqual(rest.flatMap(\.samples).map(\.uuid), ["SAMPLE-1"])
    XCTAssertTrue(third.pending.isEmpty)
    XCTAssertEqual(third.lastBackgroundSyncAt, now)
    XCTAssertNil(third.lastSyncAt, "a background pass shows as a foreground sync")
  }

  func testAnchorsMoveOnlyAfterQueueSave() async throws {
    // Two pages of steps; the run expires while the first page is being sent.
    let changes: [HealthChange] = (0..<2500).map { .added(sample($0)) }
    let health = FakeHealthStore(changes: [.stepCount: changes])
    let saved = SavedStates()
    let sync = HealthSync(state: SyncState(deviceID: "DEVICE-1"), save: saved.append)
    let expiring = ExpiringTransport(expireOn: 1, answered: false)
    let expired = await Task {
      await sync.run(health: health, transport: expiring, background: true)
    }.value

    // Every saved state with a moved anchor also holds that page in its queue.
    let key = HealthType.stepCount.rawValue
    XCTAssertFalse(saved.all.isEmpty, "nothing was saved")
    for state in saved.all where state.anchors[key] != nil {
      XCTAssertEqual(
        state.pending.flatMap(\.samples).count, 2000, "an anchor was saved without its batch")
    }
    XCTAssertEqual(expired.pending.count, 1, "the second page was read after the expiration")
    XCTAssertEqual(saved.all.last, expired)

    // A relaunch from the saved state sends both pages: every sample once, none lost.
    let relaunched = HealthSync(state: try XCTUnwrap(saved.all.last), save: saved.append)
    let calm = ExpiringTransport(expireOn: 0, answered: true)
    let done = await relaunched.run(health: health, transport: calm, now: now, background: true)
    let sent = await calm.posts.flatMap(\.samples).map(\.uuid)
    XCTAssertEqual(sent.count, 2500, "a sample was lost or sent twice")
    XCTAssertEqual(Set(sent).count, 2500)
    XCTAssertTrue(done.pending.isEmpty)
    XCTAssertEqual(done.lastBackgroundSyncAt, now)
  }
}
