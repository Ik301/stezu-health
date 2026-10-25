import Foundation
import StezuCore
import XCTest

final class RestTimerTests: XCTestCase {
  func testRestTimerUsesInjectedClock() {
    var now = Date(timeIntervalSince1970: 1_700_000_000)
    var timer = RestTimer(duration: 90, now: { now })

    XCTAssertNil(timer.remaining)
    XCTAssertEqual(timer.state, .idle)

    timer.start()
    XCTAssertEqual(timer.startedAt, now)
    XCTAssertEqual(timer.remaining, 90)

    now = now.addingTimeInterval(30)
    XCTAssertEqual(timer.remaining, 60)
    XCTAssertEqual(timer.state, .resting(remaining: 60))

    now = now.addingTimeInterval(60)
    XCTAssertEqual(timer.remaining, 0)
    XCTAssertEqual(timer.state, .done(overBy: 0))

    now = now.addingTimeInterval(15)
    XCTAssertEqual(timer.remaining, 0)
    XCTAssertEqual(timer.state, .done(overBy: 15))

    // Restarting reads the clock again, as when the next set is logged.
    timer.start()
    XCTAssertEqual(timer.remaining, 90)

    timer.stop()
    XCTAssertNil(timer.remaining)
    XCTAssertEqual(timer.state, .idle)
  }

  func testAdjustKeepsStartTime() {
    var now = Date(timeIntervalSince1970: 1_700_000_000)
    let start = now
    var timer = RestTimer(duration: 90, now: { now })

    // Idle: adjusting does nothing.
    timer.adjust(by: 15)
    XCTAssertEqual(timer.duration, 90)
    XCTAssertNil(timer.endsAt)

    timer.start()
    now = now.addingTimeInterval(10)
    timer.adjust(by: 15)
    XCTAssertEqual(timer.startedAt, start)
    XCTAssertEqual(timer.remaining, 95)
    XCTAssertEqual(timer.endsAt, start.addingTimeInterval(105))

    timer.adjust(by: -15)
    XCTAssertEqual(timer.startedAt, start)
    XCTAssertEqual(timer.remaining, 80)
    XCTAssertEqual(timer.endsAt, start.addingTimeInterval(90))

    // Shortening past the elapsed time ends the rest but keeps the start.
    timer.adjust(by: -1000)
    XCTAssertEqual(timer.duration, 0)
    XCTAssertEqual(timer.startedAt, start)
    XCTAssertEqual(timer.state, .done(overBy: 10))
  }

  func testSkipEndsRest() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var timer = RestTimer(duration: 120, now: { now })
    timer.start()
    XCTAssertEqual(timer.state, .resting(remaining: 120))

    timer.skip()
    XCTAssertEqual(timer.state, .idle)
    XCTAssertNil(timer.remaining)
    XCTAssertNil(timer.startedAt)
    XCTAssertNil(timer.endsAt)
  }
}
