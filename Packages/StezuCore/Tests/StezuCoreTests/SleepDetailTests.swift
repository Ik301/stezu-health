import Foundation
import StezuCore
import XCTest

/// S-040: the Sleep screen's model. Nights are named by the day they end on (the wake day).
final class SleepDetailTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  /// Minutes from midnight of January `day`, 2026 (negative is the evening before).
  private func at(_ day: Int, _ minutes: Double) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 1, day: day))! + minutes * 60
  }

  private func stage(_ stage: SleepStage, _ day: Int, _ from: Double, _ to: Double)
    -> SleepInterval
  {
    (start: at(day, from), end: at(day, to), stage: stage)
  }

  /// Sunday the 11th at noon.
  private var now: Date { at(11, 720) }

  /// The night ending on the 11th: in bed at 23:00, asleep 23:15, two wake-ups after falling
  /// asleep (01:00 to 01:10 and 04:00 to 04:05), asleep until 07:00, up at 07:20.
  private var lastNight: [SleepInterval] {
    [
      stage(.inBed, 11, -60, 440), stage(.awake, 11, -60, -45), stage(.asleepCore, 11, -45, 60),
      stage(.awake, 11, 60, 70), stage(.asleepDeep, 11, 70, 180), stage(.asleepREM, 11, 180, 240),
      stage(.awake, 11, 240, 245), stage(.asleepUnspecified, 11, 245, 420),
      stage(.awake, 11, 420, 440),
    ]
  }

  func testWindowBarsSpanBedtimeToFinalWake() {
    // The 10th: asleep 00:30 to 06:00. The 9th has no night. The window of 14 nights ending
    // today starts on December 29th, so the 3rd is in it and December 1st is not.
    let tenth = [stage(.asleepCore, 10, 30, 360)]
    let third = [stage(.inBed, 3, -90, 400), stage(.asleepCore, 3, -80, 390)]
    let early = [stage(.asleepCore, -30, -60, 400)]  // December 1st: outside the window
    let detail = SleepDetail.make(
      lastNight + tenth + third + early, samples: [], now: now, calendar: calendar)

    XCTAssertEqual(detail.days.count, 14)
    XCTAssertEqual(detail.days.first, at(-2, 0), "the window starts 13 days before today")
    XCTAssertEqual(detail.days.last, at(11, 0), "the window ends with last night")
    XCTAssertNil(detail.nights[at(9, 0)], "a night without data is absent, not 0")

    let last = detail.nights[at(11, 0)]
    XCTAssertEqual(last?.bedtime, at(11, -60), "bedtime is the first stage, in bed included")
    XCTAssertEqual(last?.wake, at(11, 420), "final wake is the end of the last asleep stage")
    XCTAssertEqual(last?.bedMinutes, -60)
    XCTAssertEqual(last?.wakeMinutes, 420)
    XCTAssertEqual(last?.asleep, SleepNights.nights(lastNight, calendar: calendar)[at(11, 0)])
    XCTAssertEqual(detail.nights[at(10, 0)]?.bedMinutes, 30)
    XCTAssertEqual(detail.nights[at(10, 0)]?.wakeMinutes, 360)
    XCTAssertEqual(detail.nights[at(3, 0)]?.bedMinutes, -90)

    // The shared clock axis covers every bar in whole hours.
    XCTAssertEqual(detail.axis, -120...420)
    // The usual lines are the medians of the window's bedtimes and wakes.
    XCTAssertEqual(detail.usualBed, -60)
    XCTAssertEqual(detail.usualWake, 390)
    // The usual night is S-037's: the median of up to 30 recorded nights.
    let summary = SleepSummary.make(lastNight + tenth + third + early, now: now, calendar: calendar)
    XCTAssertEqual(detail.usual, summary.usual)
    XCTAssertEqual(detail.usualNights, 4)
  }

  func testWakeUpsCountAwakeAfterSleepOnset() {
    let detail = SleepDetail.make(lastNight, samples: [], now: now, calendar: calendar)
    let night = detail.nights[at(11, 0)]
    // Awake before falling asleep and after the final wake are not wake-ups.
    XCTAssertEqual(night?.wakeUps, 2)
    XCTAssertEqual(night?.awakeAfterOnset, 15 * 60)

    // Two apps writing the same wake-up count it once; a night without any has none.
    let doubled = [
      stage(.asleepCore, 11, 0, 100), stage(.awake, 11, 100, 110), stage(.awake, 11, 105, 112),
      stage(.asleepCore, 11, 112, 400),
    ]
    let twice = SleepDetail.make(doubled, samples: [], now: now, calendar: calendar)
    XCTAssertEqual(twice.nights[at(11, 0)]?.wakeUps, 1)
    XCTAssertEqual(twice.nights[at(11, 0)]?.awakeAfterOnset, 12 * 60)
    let calm = SleepDetail.make(
      [stage(.asleepCore, 11, 0, 400)], samples: [], now: now, calendar: calendar)
    XCTAssertEqual(calm.nights[at(11, 0)]?.wakeUps, 0)
    XCTAssertEqual(calm.nights[at(11, 0)]?.awakeAfterOnset, 0)
  }

  func testStageTotalsCountUnspecifiedAsCore() {
    let night = SleepDetail.make(lastNight, samples: [], now: now, calendar: calendar)
      .nights[at(11, 0)]
    XCTAssertEqual(night?.totals[.core], (105 + 175) * 60, "unspecified asleep counts as Core")
    XCTAssertEqual(night?.totals[.deep], 110 * 60)
    XCTAssertEqual(night?.totals[.rem], 60 * 60)
    XCTAssertEqual(night?.totals[.awake], (15 + 10 + 5 + 20) * 60, "every awake stretch")
    XCTAssertEqual(night?.stages.count, 8, "in bed is not a stage lane")
    XCTAssertEqual(night?.stages.filter { $0.lane == .core }.count, 2)
  }

  func testOvernightLineUsesAsleepIntervalsOnly() {
    func sample(_ type: HealthType, _ minutes: Double, _ value: Double) -> HealthSample {
      HealthSample(type: type, date: at(11, minutes), sourceName: "Strap", value: value)
    }
    let samples = [
      // Asleep: these count.
      sample(.heartRate, 0, 58), sample(.heartRate, 100, 49), sample(.heartRate, 300, 66),
      sample(.respiratoryRate, 30, 13), sample(.respiratoryRate, 200, 15.5),
      sample(.heartRateVariability, 90, 60), sample(.heartRateVariability, 250, 80),
      sample(.heartRateVariability, 380, 70),
      // Awake before sleep, during a wake-up, after the final wake, the afternoon: these do not.
      sample(.heartRate, -50, 90), sample(.heartRate, 65, 95), sample(.heartRate, 430, 88),
      sample(.heartRate, 900, 120), sample(.respiratoryRate, 242, 22),
      sample(.heartRateVariability, 435, 20),
    ]
    let detail = SleepDetail.make(lastNight, samples: samples, now: now, calendar: calendar)
    let overnight = detail.overnight[at(11, 0)]
    XCTAssertEqual(overnight?.heartRate, 49...66)
    XCTAssertEqual(overnight?.breathing, 13...15.5)
    XCTAssertEqual(overnight?.hrv, 70, "HRV is the median of the readings while asleep")
    XCTAssertEqual(overnight?.confidence.reason, "8 readings while asleep")

    // No readings while asleep: every number is absent, not 0.
    let none = SleepDetail.make(
      lastNight, samples: [sample(.heartRate, 900, 70)], now: now, calendar: calendar)
    XCTAssertNil(none.overnight[at(11, 0)]?.heartRate)
    XCTAssertNil(none.overnight[at(11, 0)]?.breathing)
    XCTAssertNil(none.overnight[at(11, 0)]?.hrv)
    XCTAssertEqual(none.overnight[at(11, 0)]?.confidence.level, .low)
  }
}
