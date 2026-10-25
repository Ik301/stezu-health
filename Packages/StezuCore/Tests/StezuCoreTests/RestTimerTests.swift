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
}
