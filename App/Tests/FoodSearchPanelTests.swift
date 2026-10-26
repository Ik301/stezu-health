import StezuCore
import XCTest

@testable import StezuHealth

final class FoodSearchPanelTests: XCTestCase {
  func testFixtureGroupsAndDetailLines() throws {
    let groups = try FoodSearchClient.decode(Data(UITestFixtures.searchReply.utf8))
    for section in FoodSearchPanel.sections {
      let items = groups.first { $0.source == section.source }?.items ?? []
      XCTAssertEqual(items.count, 1, section.title)
    }
    let details = groups.flatMap(\.items).map(FoodSearchPanel.detail)
    XCTAssertEqual(
      details, ["North Hall, South Hall · 4 oz", "Example Dairy · 1 cup", "1 burrito"])

    let estimate = try FoodSearchClient.decode(Data(UITestFixtures.estimateReply.utf8))
    let rough = try XCTUnwrap(estimate.first?.items.first)
    XCTAssertTrue(rough.isRough)
    XCTAssertEqual(FoodSearchPanel.detail(rough), "1 bowl")
  }
}
