import XCTest

@testable import StezuHealth

final class HomeViewTests: XCTestCase {
  func testPlaceholderShowsThreeCardsWithDashes() {
    let cards = HomePlaceholder.cards
    XCTAssertEqual(cards.map(\.label), ["Data", "Food", "Workout"])
    XCTAssertTrue(cards.allSatisfy { $0.value == "--" })
    XCTAssertFalse(cards.contains { $0.value == "0" })
    XCTAssertFalse(HomePlaceholder.coreVersion.isEmpty)
  }
}
