import Foundation
import StezuCore
import SwiftUI

/// Where the app's records live.
enum StorageMode: Sendable, Equatable {
  /// The normal on-device store.
  case disk
  /// Memory only, so every launch starts empty. The `-uitest` default.
  case memory
  /// A store in this temporary folder that survives a relaunch (`-uitest-persist`), for resume
  /// and offline-queue tests. `-uitest-reset` empties the folder at launch.
  case temporary(URL)
}

/// The outside world, chosen once at launch and passed down as `\.appEnvironment`.
/// Live: the disk store, HealthKit, the VM server and the camera. `-uitest`: an in-memory store,
/// FakeHealthStore, FakeVMTransport and a fixture photo, so the simulator needs no camera, Health
/// data or network.
struct AppEnvironment: Sendable {
  /// Launch arguments the app understands. UI tests pass them through `UITestApp.launch`.
  enum Argument {
    static let uiTest = "-uitest"
    /// Followed by a name: seeds the synthetic fixture data a story defines.
    static let scenario = "-uitest-scenario"
    /// The fake VM transport starts offline.
    static let offline = "-uitest-offline"
    /// Keep the store in a temporary folder across relaunches.
    static let persist = "-uitest-persist"
    /// Empty that folder first.
    static let reset = "-uitest-reset"
  }

  var isUITest: Bool
  var storage: StorageMode
  /// The `-uitest-scenario` name; nil in the live app.
  var scenario: String?
  var healthStore: any HealthStore
  var vmTransport: any VMTransport
  var photoSource: any PhotoSource
  /// Settings' server address and token: UserDefaults and the Keychain, or memory in `-uitest`.
  var serverSettings: any ServerSettingsStore
  /// Meal photos saved at the shutter (S-012), stored according to `storage`.
  var mealCaptures: MealCaptureStore
  /// Finished workouts, for last-session numbers (S-005). Nothing stores them yet, so the live
  /// app has none; `-uitest-scenario workout-history` seeds synthetic ones.
  var workoutHistory: [WorkoutSession] = []
  /// The rest's Live Activity and zero notification (S-006): live on the phone, a recorder in
  /// `-uitest` and previews.
  var restAlerts: any RestAlerts = FakeRestAlerts()
  /// Import program's file source: the Files picker, or a synthetic program in `-uitest`.
  var programFilePicker: ProgramFilePicker
  /// Whether Data has shown the Health sheet (S-020). Memory unless the live app passes defaults.
  var healthConnection = HealthConnection(defaults: nil)
  /// The time Data reads its week at: the clock, or a fixed synthetic Sunday in `-uitest`.
  var now: @Sendable () -> Date = { Date() }
  var healthSync = HealthSync(state: SyncState())  // Health to the VM server (S-028)
  /// Logged meals a scenario seeds (S-023); the live app's meals are in `mealCaptures`.
  var mealHistory: [LoggedMeal] = []
  /// Barcode mode's codes (S-016): VisionKit's scanner, or a synthetic code in `-uitest`.
  var barcodeSource = BarcodeSource.camera

  /// The services the phone uses. The VM transport stays unconfigured until Settings has a
  /// server address and token, then sends to that server with the token.
  static func live() -> AppEnvironment {
    let settings = DeviceServerSettingsStore()
    return AppEnvironment(
      isUITest: false, storage: .disk, scenario: nil, healthStore: HealthKitStore(),
      vmTransport: settings.load().transport(), photoSource: LiveCameraPhotoSource(),
      serverSettings: settings, mealCaptures: MealCaptureStore(storage: .disk),
      restAlerts: LiveRestAlerts(), programFilePicker: .files,
      healthConnection: HealthConnection(defaults: .standard),
      healthSync: HermesSyncFile.engine(storage: .disk))
  }

  /// Fakes only, for `-uitest` launches and SwiftUI previews.
  static func fakes(scenario: String? = nil, offline: Bool = false) -> AppEnvironment {
    AppEnvironment(
      isUITest: true, storage: .memory, scenario: scenario,
      healthStore: FakeHealthStore(
        samples: UITestFixtures.healthSamples(scenario: scenario)
          + UITestFixtures.weekHealthSamples(scenario: scenario)
          + UITestFixtures.strapSamples(scenario: scenario)
          + UITestFixtures.foodWeekWorkouts(scenario: scenario),
        sleep: UITestFixtures.sleep(scenario: scenario),
        changes: UITestFixtures.healthChanges(scenario: scenario)),
      vmTransport: FakeVMTransport(
        routes: UITestFixtures.vmRoutes, offline: offline,
        held: UITestFixtures.heldRoutes(scenario: scenario)),
      photoSource: FixturePhotoSource(), serverSettings: MemoryServerSettingsStore(),
      mealCaptures: MealCaptureStore(
        storage: .memory, seed: UITestFixtures.foodHistory(scenario: scenario)),
      workoutHistory: UITestFixtures.workoutHistory(scenario: scenario),
      programFilePicker: .fixture(UITestFixtures.programFile(scenario: scenario)),
      healthConnection: HealthConnection(
        defaults: nil, asked: UITestFixtures.isDataWeek(scenario)),
      now: UITestFixtures.clock(scenario: scenario),
      mealHistory: UITestFixtures.loggedMeals(scenario: scenario),
      barcodeSource: .fixture(UITestFixtures.barcode(scenario: scenario)))
  }

  /// After Settings saves a server, the live app sends to it. `-uitest` keeps the fake.
  mutating func useServer(_ settings: ServerSettings) {
    guard !isUITest else { return }
    vmTransport = settings.transport()
  }

  /// Live services unless the launch arguments contain `-uitest`.
  static func fromLaunch(arguments: [String] = ProcessInfo.processInfo.arguments)
    -> AppEnvironment
  {
    guard arguments.contains(Argument.uiTest) else { return live() }
    var scenario: String?
    if let index = arguments.firstIndex(of: Argument.scenario), index + 1 < arguments.count {
      scenario = arguments[index + 1]
    }
    var environment = fakes(scenario: scenario, offline: arguments.contains(Argument.offline))
    if arguments.contains(Argument.persist) {
      let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("stezu-uitest-store", isDirectory: true)
      if arguments.contains(Argument.reset) {
        try? FileManager.default.removeItem(at: folder)
      }
      environment.storage = .temporary(folder)
      environment.mealCaptures = MealCaptureStore(storage: environment.storage)
    }
    return environment
  }
}

private struct AppEnvironmentKey: EnvironmentKey {
  static let defaultValue = AppEnvironment.fakes()
}

extension EnvironmentValues {
  /// The services chosen at launch. Previews get the fakes.
  var appEnvironment: AppEnvironment {
    get { self[AppEnvironmentKey.self] }
    set { self[AppEnvironmentKey.self] = newValue }
  }
}
