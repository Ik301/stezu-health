import StezuCore
import XCTest

/// S-053: Isaac's own places name every visit inside them, before any looked-up name, on the
/// phone only. Coordinates are made up (D-034); 0.0004 degrees of latitude is about 44 m.
final class PlaceNamesTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_014_400)

  /// Visits a (10.25), b (10.2504, 44 m north) and c (10.26, about 1.1 km north).
  private func visits() -> [PlaceRecord] {
    var log = LocationLog()
    for (index, latitude) in [10.25, 10.2504, 10.26].enumerated() {
      let arrival = now - Double(3 - index) * 3600
      _ = log.apply(
        .visit(
          arrival: arrival, departure: arrival + 1800, latitude: latitude, longitude: -30.5,
          accuracy: 40), at: now)
    }
    return log.places
  }

  func testSmallestEnclosingPlaceWins() {
    let (a, b, c) = (visits()[0], visits()[1], visits()[2])
    let campus = MyPlace(id: "1", name: "Campus", latitude: 10.25, longitude: -30.5, radiusM: 400)
    let gym = MyPlace(id: "2", name: "Gym", latitude: 10.25, longitude: -30.5, radiusM: 60)
    let mine = MyPlaces([campus, gym])
    XCTAssertEqual(mine.place(for: a)?.name, "Gym", "the smaller circle wins where both hold it")
    XCTAssertEqual(mine.place(for: b)?.name, "Gym", "44 m away is inside 60 m")
    XCTAssertNil(mine.place(for: c), "1.1 km away is outside both circles")
    XCTAssertEqual(MyPlaces([gym, campus]).place(for: a)?.name, "Gym", "order does not matter")
  }

  func testMyPlaceOverridesLookedUpName() {
    let (a, b, c) = (visits()[0], visits()[1], visits()[2])
    let looked = [a.id: "Library", c.id: "Dining hall"]
    let mine = MyPlaces([
      MyPlace(id: "1", name: "Gym", latitude: 10.2502, longitude: -30.5, radiusM: 75)
    ])
    XCTAssertEqual(mine.name(a, looked: looked), "Gym")
    XCTAssertEqual(mine.name(b, looked: looked), "Gym", "an unnamed visit inside takes it too")
    XCTAssertEqual(mine.name(c, looked: looked), "Dining hall", "outside keeps the looked-up name")
    XCTAssertNil(MyPlaces().name(b, looked: looked), "no name leaves the visit's times")
  }

  func testDeletingPlaceRestoresFallback() async {
    let a = visits()[0]
    let saved = SavedPlaces()
    let store = MyPlacesStore { saved.set($0) }
    var gym = MyPlace(
      id: "1", name: " Gym ", note: " Lift on Mon and Thu ", latitude: 10.25, longitude: -30.5)
    var mine = await store.set(gym)
    XCTAssertEqual(mine.name(a, looked: [a.id: "Library"]), "Gym", "the name is trimmed")
    XCTAssertEqual(mine.places.first?.note, "Lift on Mon and Thu")
    gym.name = "Weights"
    gym.note = " "
    mine = await store.set(gym)
    XCTAssertEqual(mine.places.count, 1, "an edit replaces the place by id")
    XCTAssertEqual(mine.name(a, looked: [:]), "Weights")
    XCTAssertNil(mine.places.first?.note, "an empty note is no note")
    mine = await store.set(gym, delete: true)
    XCTAssertEqual(mine.name(a, looked: [a.id: "Library"]), "Library")
    XCTAssertEqual(saved.get(), MyPlaces(), "the delete is saved")
    let reread = await store.places
    XCTAssertEqual(reread, mine)
  }
}

private final class SavedPlaces: @unchecked Sendable {
  private let lock = NSLock()
  private var places: MyPlaces?
  func set(_ places: MyPlaces) { lock.withLock { self.places = places } }
  func get() -> MyPlaces? { lock.withLock { places } }
}
