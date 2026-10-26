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

  var body: some View {
    VStack(spacing: 0) {
      topBar
      Spacer()
      if cameraAllowed == false { deniedMessage }
      if captureFailed {
        Text("Could not take the photo.").foregroundStyle(.white)
          .accessibilityIdentifier("food.error")
      }
      Spacer()
      bottomBar
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black.overlay { cameraImage }.clipped().ignoresSafeArea(edges: .top))
    .task { await startCamera() }
    .onDisappear { (environment.photoSource as? LiveCameraPhotoSource)?.stop() }
    .sheet(item: $captured) { _ in PhotoMatchSheet(state: match) }
  }

  @ViewBuilder private var cameraImage: some View {
    if let live = environment.photoSource as? LiveCameraPhotoSource, cameraAllowed == true {
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
      Button("History") {}
        .font(.system(size: Theme.labelSize, weight: .medium)).foregroundStyle(Theme.text)
        .frame(width: 64, height: 44).background(Capsule().fill(Theme.card))
        .accessibilityIdentifier("food.history")
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
      match = await MealMatcher(environment: environment).match(meal)
    } catch {
      captureFailed = true
    }
  }
}
