import StezuCore
import XCTest

@testable import StezuHealth

final class RestActivityControllerTests: XCTestCase {
  func testLoggedSetStartsActivityUntilRestEnds() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    var now = start
    let alerts = FakeRestAlerts()
    var rest = RestActivityController(alerts: alerts, now: { now })
    let bench = TemplateExercise(
      key: "bench", name: "Bench press", sets: 3, repsLow: 6, repsHigh: 10, restSeconds: 150)
    XCTAssertEqual(RestActivityController.text(rest.remaining), "--")
    XCTAssertTrue(alerts.calls.isEmpty)

    // Logging a set starts the rest and the Live Activity at the template's rest, no tap.
    rest.setLogged(bench, setLabel: "Set 1 of 3")
    var alert = RestAlert(
      exerciseName: "Bench press", setLabel: "Set 1 of 3", startedAt: start,
      endsAt: start.addingTimeInterval(150))
    XCTAssertEqual(alerts.calls, [.start(alert)])
    XCTAssertEqual(RestActivityController.text(rest.remaining), "2:30")

    // Mid-rest: ticking does nothing; +15 and -15 move only the end.
    now = start.addingTimeInterval(30)
    rest.tick()
    XCTAssertEqual(alerts.calls.count, 1)
    rest.adjust(by: 15)
    alert.endsAt = start.addingTimeInterval(165)
    XCTAssertEqual(alerts.calls.last, .update(alert))
    XCTAssertEqual(rest.startedAt, start)
    XCTAssertEqual(RestActivityController.text(rest.remaining), "2:15")
    rest.adjust(by: -15)
    alert.endsAt = start.addingTimeInterval(150)
    XCTAssertEqual(alerts.calls.last, .update(alert))
    XCTAssertEqual(rest.startedAt, start)

    // At zero the rest and the activity end.
    now = start.addingTimeInterval(150)
    rest.tick()
    XCTAssertEqual(alerts.calls.last, .end)
    XCTAssertNil(rest.timer)
    XCTAssertEqual(RestActivityController.text(rest.remaining), "--")

    // Skip ends the next rest at once; a second skip changes nothing.
    rest.setLogged(bench, setLabel: "Set 2 of 3")
    rest.skip()
    rest.skip()
    XCTAssertEqual(alerts.calls.count, 6)
    XCTAssertEqual(alerts.calls.last, .end)
    XCTAssertNil(rest.endsAt)
  }
}
