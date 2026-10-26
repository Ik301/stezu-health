import StezuCore
import SwiftUI
import UIKit

/// Food opens straight into the camera (S-012). The shutter saves the photo locally, then a sheet
/// shows "Matching...". In `-uitest` the fixture plate stands in for the camera image.
struct FoodView: View {
  var goHome: () -> Void = {}
  @Environment(\.appEnvironment) private var environment
  @Environment(\.openURL) private var openURL
  @State private var mode = "Photo"
  @State private var cameraAllowed: Bool?
  @State private var captured: CapturedMeal?
  @State private var match = MatchState.matching
  @State private var captureFailed = false
  @State private var today: String?
  @State private var query = ""
  @State private var picked: PickedItem?
  /// The meal just logged, while its undo toast shows.
  @State private var logged: UUID?
  /// Whether Health took that meal (S-018).
  @State private var loggedInHealth: Bool?
  @State private var logFailed = false
  @State private var barcode = BarcodeState.scanning
  /// Today's logged food for the top strip (S-019); nil until loaded.
  @State private var day: FoodDay?
  @State private var showingHistory = false
  @FocusState private var searching: Bool

  var body: some View {
    VStack(spacing: 0) {
      topBar
      todayStrip.padding(.top, 10)
      searchBar.padding(.top, 10)
      if trimmedQuery.isEmpty {
        Spacer()
        if mode == "Barcode" {
          BarcodeStatusView(state: barcode) {
            mode = "Photo"
            searching = true
          }
        }
        if cameraAllowed == false { deniedMessage }
        if captureFailed {
          Text("Could not take the photo.").foregroundStyle(.white)
            .accessibilityIdentifier("food.error")
        }
        if logFailed {
          Text("Could not save the meal.").foregroundStyle(.white)
            .accessibilityIdentifier("food.log.error")
        }
        Spacer()
      } else {
        FoodSearchPanel(query: trimmedQuery) { item in
          searching = false
          picked = PickedItem(item: item)
        }
        .padding(.vertical, 8)
      }
      if let logged { undoToast(logged) }
      bottomBar
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black.overlay { cameraImage }.clipped().ignoresSafeArea(edges: .top))
    .task {
      if environment.isUITest {
        await environment.mealCaptures.seedPhotos(FixturePhotoSource.plateJPEG())
      }
      await loadToday()
      await startCamera()
      await retryQueue()
    }
    .task(id: mode) { await barcodeMode() }
    .onDisappear { (environment.photoSource as? LiveCameraPhotoSource)?.stop() }
    // Reading match and today here makes the body depend on them, so the sheet updates.
    .sheet(item: $captured) { [match, today] meal in
      PhotoMatchSheet(state: match, today: today) { logMeal($0, id: meal.id) }
    }
  }

  private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

  /// Typing opens search results over the camera (S-014); a pick opens the item list.
  private var searchBar: some View {
    TextField("Search food", text: $query).focused($searching).autocorrectionDisabled()
      .font(.system(size: Theme.subtitleSize)).foregroundStyle(Theme.text)
      .padding(.horizontal, 16).frame(height: 44).background(Capsule().fill(Theme.card))
      .accessibilityIdentifier("food.search.field")
      .sheet(item: $picked) { picked in
        PhotoMatchSheet(
          state: .matched(PhotoMatch(mealId: picked.id.uuidString, items: [picked.item]))
        ) { logMeal($0, id: picked.id) }
      }
  }

  @ViewBuilder private var cameraImage: some View {
    if mode == "Barcode", case .camera = environment.barcodeSource, cameraAllowed == true,
      BarcodeScannerView.available
    {
      BarcodeScannerView { code in Task { await scanned(code) } }
    } else if let live = environment.photoSource as? LiveCameraPhotoSource, cameraAllowed == true {
      CameraPreview(session: live.session)
    } else if environment.isUITest, let plate = UIImage(data: FixturePhotoSource.plateJPEG()) {
      Image(uiImage: plate).resizable().scaledToFill()
        .accessibilityLabel("Camera").accessibilityIdentifier("food.camera.preview")
    }
  }

  private var topBar: some View {
    HStack {
      Button(action: goHome) {
        Image(systemName: "house").font(.system(size: 17, weight: .medium))
          .foregroundStyle(Theme.text).frame(width: 44, height: 44)
          .background(Circle().fill(Theme.card))
      }
      .accessibilityLabel("Home").accessibilityIdentifier("nav.home")
      Text("Food").font(.system(size: Theme.subtitleSize, weight: .semibold))
        .foregroundStyle(Theme.text).padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Theme.card))
        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("screen.food.title")
      Spacer()
      HStack(spacing: 0) {
        ForEach(["Photo", "Barcode"], id: \.self) { item in
          Button(item) { mode = item }
            .font(.system(size: Theme.labelSize, weight: .medium))
            .foregroundStyle(item == mode ? Theme.invertedText : Theme.text)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(item == mode ? Theme.invertedCard : Color.clear))
            .accessibilityValue(item == mode ? "on" : "off")
            .accessibilityIdentifier("food.mode.\(item.lowercased())")
        }
      }
      .padding(3).background(Capsule().fill(Color.white))
    }
  }

  private var bottomBar: some View {
    HStack {
      Button("History") { showingHistory = true }
        .font(.system(size: Theme.labelSize, weight: .medium)).foregroundStyle(Theme.text)
        .frame(width: 64, height: 44).background(Capsule().fill(Theme.card))
        .accessibilityIdentifier("food.history")
        .sheet(isPresented: $showingHistory) { FoodHistory { Task { await loadToday() } } }
      Spacer()
      if mode == "Photo" {
        Button {
          Task { await shutter() }
        } label: {
          Circle().strokeBorder(Color.white, lineWidth: 4).frame(width: 74, height: 74)
            .overlay(Circle().fill(Color.white).padding(8))
        }
        .accessibilityLabel("Shutter").accessibilityIdentifier("food.shutter")
        .disabled(cameraAllowed != true)
      }
      Spacer()
      Color.clear.frame(width: 64, height: 44)
    }
  }

  /// Today's kcal and protein ranges and meal count, "--" with none; no target (D-032).
  private var todayStrip: some View {
    HStack(spacing: 12) {
      Text("Today").fontWeight(.semibold)
      Text(PhotoMatchSheet.range(day?.kcal, unit: "kcal")).accessibilityIdentifier(
        "food.strip.kcal")
      Text(PhotoMatchSheet.range(day?.proteinG, unit: "g protein"))
        .accessibilityIdentifier("food.strip.protein")
      Spacer(minLength: 0)
      Text(day?.mealCount.map { "\($0) meal\($0 == 1 ? "" : "s")" } ?? "-- meals")
        .accessibilityIdentifier("food.strip.meals")
    }
    .font(.system(size: Theme.labelSize, weight: .medium)).foregroundStyle(Theme.text)
    .padding(.horizontal, 14).frame(height: 32).background(Capsule().fill(Theme.card))
  }

  private func loadToday() async {
    let meals = await environment.mealCaptures.logged()
    day = FoodDay.on(environment.now(), meals: meals)
  }

  private var deniedMessage: some View {
    VStack(spacing: 12) {
      Text("Camera access is off. Turn it on in Settings, Ingest, Camera.")
        .multilineTextAlignment(.center).foregroundStyle(.white)
        .accessibilityIdentifier("food.camera.denied")
      Button("Open Settings") {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
      }
      .foregroundStyle(.white)
    }
    .padding(16).background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(.black))
  }

  /// After Log: "Meal logged" with Undo for 8 seconds over the camera.
  private func undoToast(_ id: UUID) -> some View {
    HStack {
      Text("Meal logged").accessibilityIdentifier("food.logged.toast")
      if let inHealth = loggedInHealth {
        Text(inHealth ? "In Health" : "Not in Health").font(.system(size: Theme.labelSize))
          .foregroundStyle(Theme.label).accessibilityIdentifier("food.logged.health")
      }
      Spacer()
      Button("Undo") {
        logged = nil
        Task {
          await environment.mealCaptures.unlog(id)
          try? await environment.healthStore.deleteFood(syncIdentifier: id.uuidString)
          await loadToday()
        }
      }
      .fontWeight(.semibold).accessibilityIdentifier("food.logged.undo")
    }
    .font(.system(size: Theme.subtitleSize)).foregroundStyle(Theme.invertedText)
    .padding(.horizontal, 18).frame(height: 48)
    .background(Capsule().fill(Theme.invertedCard)).padding(.bottom, 10)
    .task(id: id) {
      guard (try? await Task.sleep(nanoseconds: 8_000_000_000)) != nil else { return }
      logged = nil
    }
  }

  /// The single Log tap: the items are saved as confirmed and the sheet closes to the camera.
  /// Then the meal goes to Health as one food entry (S-018); a denied write keeps the meal.
  private func logMeal(_ items: [MatchedItem], id: UUID) {
    let meal = LoggedMeal(id: id, loggedAt: environment.now(), items: items)
    (captured, picked, query) = (nil, nil, "")
    let store = environment.mealCaptures
    Task {
      do {
        let written = try await MealHealth.log(meal, health: environment.healthStore) {
          try await store.log($0)
        }
        (logged, loggedInHealth, logFailed) = (meal.id, written.inHealth, false)
        await loadToday()
      } catch {
        logFailed = true
      }
    }
  }

  private func startCamera() async {
    let allowed = await environment.photoSource.authorize()
    cameraAllowed = allowed
    if allowed { (environment.photoSource as? LiveCameraPhotoSource)?.start() }
  }

  private func shutter() async {
    do {
      captureFailed = false
      let meal = try await MealCapture(environment: environment).shutter()
      match = .matching
      captured = meal
      let result = await MealMatcher(environment: environment).match(meal)
      if result == .pending {
        let pending = await environment.mealCaptures.queue().pendingCount(on: environment.now())
        today = MealQueue.todayText(loggedKcal: nil, pending: pending)
      }
      match = result
    } catch {
      captureFailed = true
    }
  }

  /// Barcode mode hands the camera to the scanner (S-016); Photo mode takes it back. In `-uitest`
  /// the fixture code arrives 8 seconds after the switch.
  private func barcodeMode() async {
    barcode = .scanning
    let live = environment.photoSource as? LiveCameraPhotoSource
    guard mode == "Barcode" else {
      if cameraAllowed == true { live?.start() }
      return
    }
    live?.stop()
    guard case .fixture(let code) = environment.barcodeSource,
      (try? await Task.sleep(nanoseconds: 8_000_000_000)) != nil
    else { return }
    await scanned(code)
  }

  /// GET /barcode for a scanned code; a product opens the item list at 1 serving, ready to Log.
  private func scanned(_ code: String) async {
    guard mode == "Barcode", barcode != .lookingUp, picked == nil, captured == nil,
      BarcodeClient.isGTIN(code)
    else { return }
    barcode = .lookingUp
    do {
      switch try await BarcodeClient(transport: environment.vmTransport).lookup(code) {
      case .found(let item): (barcode, picked) = (.scanning, PickedItem(item: item))
      case .notFound: barcode = .notFound
      }
    } catch {
      barcode = .failed
    }
  }

  /// Opening Food retries pending meals oldest first (S-017). The newest one matched now opens
  /// in the sheet, ready to Log; a meal still pending stays in the queue.
  private func retryQueue() async {
    guard let meal = await MealMatcher(environment: environment).retryQueue(),
      let found = meal.match, captured == nil
    else { return }
    captured = CapturedMeal(id: meal.id, capturedAt: meal.capturedAt)
    match = .matched(found)
  }
}

/// A search pick waiting in the item list sheet.
struct PickedItem: Identifiable {
  let id = UUID()
  let item: MatchedItem
}
