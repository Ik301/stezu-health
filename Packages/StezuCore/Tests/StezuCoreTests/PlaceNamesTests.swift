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

  /// S-054: the nearest point of interest beats the placemark, which beats the campus-wide area.
  func testPOINameBeatsAreaOfInterest() async {
    let all = PlaceLookup(pointOfInterest: "Library", placemark: "North hall", area: "Campus")
    XCTAssertEqual(all.best, "Library")
    XCTAssertEqual(PlaceLookup(placemark: "North hall", area: "Campus").best, "North hall")
    XCTAssertEqual(PlaceLookup(area: "Campus").best, "Campus")
    XCTAssertNil(PlaceLookup().best)
    XCTAssertNil(PlaceLookup.placeName("12 Elm St", address: "12 Elm St, Town"), "a street")
    XCTAssertEqual(PlaceLookup.placeName("North hall", address: "12 Elm St"), "North hall")
    XCTAssertEqual(PlaceLookup.radius(accuracy: 10), 80, "at least 40 m, plus 40")
    XCTAssertEqual(PlaceLookup.radius(accuracy: 70), 110)
    XCTAssertEqual(PlaceLookup.radius(accuracy: 500), 150, "capped")

    let (a, b) = (visits()[0], visits()[1])
    let geocoder = FakeReverseGeocoder(names: [10.25: "Library"], area: "Campus")
    let names = await PlaceNames(geocoder: geocoder).name([a, b])
    XCTAssertEqual(names, [a.id: "Library", b.id: "Campus"], "the area only without a POI")
  }

  /// S-054: a place-names.json from the area-first lookup (a bare map, version 1) is looked up
  /// again once: Apple's old name is replaced, his own label stays, at most 10 a launch, and
  /// never again after a relaunch. A throttling error stops the launch's lookups.
  func testVersionOneNamesAreLookedUpAgainOnce() async throws {
    let (a, b, c) = (visits()[0], visits()[1], visits()[2])
    let old = [a.id: "Campus", b.id: "Study room", c.id: "Campus"]
    let file = try JSONEncoder().encode(old)
    let saved = try XCTUnwrap(SavedPlaceNames.decode(file))
    XCTAssertEqual(saved, SavedPlaceNames(names: old), "a bare map is version 1")
    let geocoder = FakeReverseGeocoder(
      names: [10.25: "Library", 10.2504: "Dining hall"], area: "Campus")
    let written = SavedBook()
    let names = PlaceNames(saved: saved, geocoder: geocoder) { written.set($0) }

    let first = await names.name([a, b, c])
    XCTAssertEqual(first, [a.id: "Library", b.id: "Study room", c.id: "Campus"])
    _ = await names.name([a, b, c])
    var lookups = await geocoder.lookups
    XCTAssertEqual(lookups, 3, "each old name once a launch")
    let book = try XCTUnwrap(written.get())
    XCTAssertEqual(book.versions, [a.id: 2, b.id: 2, c.id: 2])
    XCTAssertEqual(SavedPlaceNames.decode(try JSONEncoder().encode(book)), book)

    let relaunched = PlaceNames(saved: book, geocoder: geocoder) { _ in }
    _ = await relaunched.name([a, b, c])
    lookups = await geocoder.lookups
    XCTAssertEqual(lookups, 3, "version 2 names are not looked up again")

    var log = LocationLog()
    for minute in 0..<12 {
      let arrival = now + Double(minute) * 60
      _ = log.apply(
        .visit(arrival: arrival, departure: nil, latitude: 10.3, longitude: -30.5, accuracy: 40),
        at: now)
    }
    let twelve = SavedPlaceNames(
      names: Dictionary(uniqueKeysWithValues: log.places.map { ($0.id, "Campus") }))
    let counted = FakeReverseGeocoder(names: [:], area: "Campus")
    _ = await PlaceNames(saved: twelve, geocoder: counted) { _ in }.name(log.places)
    lookups = await counted.lookups
    XCTAssertEqual(lookups, 10, "at most 10 old names a launch")

    let throttling = FakeReverseGeocoder(names: [:], area: "Campus", limit: 1)
    let limited = PlaceNames(geocoder: throttling)
    _ = await limited.name(log.places)
    _ = await limited.name(log.places)
    lookups = await throttling.lookups
    XCTAssertEqual(lookups, 1, "nothing more after a throttling error")
  }
}

private final class SavedBook: @unchecked Sendable {
  private let lock = NSLock()
  private var book: SavedPlaceNames?
  func set(_ book: SavedPlaceNames) { lock.withLock { self.book = book } }
  func get() -> SavedPlaceNames? { lock.withLock { book } }
}

private final class SavedPlaces: @unchecked Sendable {
  private let lock = NSLock()
  private var places: MyPlaces?
  func set(_ places: MyPlaces) { lock.withLock { self.places = places } }
  func get() -> MyPlaces? { lock.withLock { places } }
}
