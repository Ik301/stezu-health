import StezuCore
import SwiftUI

/// Server address and token, typed once. Save writes them to the settings store (the token to
/// the Keychain) and hands them to the app, which rebuilds its VM transport. Test connection
/// sends GET /health with the saved settings (the fake transport under `-uitest`).
struct SettingsView: View {
  @Environment(\.appEnvironment) private var environment
  /// Called after a save with the stored settings.
  var saved: (ServerSettings) -> Void = { _ in }

  @State private var stored = ServerSettings()
  @State private var address = ""
  @State private var token = ""
  @State private var status = ServerConnection.untested.text
  @State private var syncText = "--"
  @State private var backgroundText = "--"

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spaceMd) {
      Text("Settings")
        .textStyle(.title1)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("screen.settings.title")
      label("Server address")
      field(TextField("Server address", text: $address).keyboardType(.URL), id: "settings.address")
      label("Token")
      field(SecureField("Token", text: $token), id: "settings.token")
      HStack {
        label("Saved token")
        Spacer()
        Text(stored.maskedToken).accessibilityIdentifier("settings.token.saved")
      }
      HStack(spacing: Theme.spaceMd) {
        pill("Save", id: "settings.save", action: save)
        pill("Test connection", id: "settings.test") { Task { await test() } }
      }
      Text(status)
        .textStyle(.subtitle)
        .accessibilityIdentifier("settings.status")
      HStack {
        label("Hermes sync")  // S-028
        Spacer()
        Text(syncText).accessibilityIdentifier("settings.sync.status")
      }
      HStack {
        label("Background sync")  // S-033
        Spacer()
        Text(backgroundText).accessibilityIdentifier("settings.sync.background")
      }
      pill("Sync now", id: "settings.sync.now") {
        Task { syncText = HermesSyncFile.text(await environment.syncHermes()) }
      }
      Spacer(minLength: 0)
    }
    .foregroundStyle(Theme.ink)
    .padding(Theme.spaceLg)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Theme.ground.ignoresSafeArea())
    .onAppear {
      stored = environment.serverSettings.load()
      address = stored.address
    }
    .task {  // live while open, so a meal synced in the background shows (S-029)
      while !Task.isCancelled {
        let state = await environment.healthSync.state
        syncText = HermesSyncFile.text(state)
        backgroundText = HermesSyncFile.time(state.lastBackgroundSyncAt)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
      }
    }
  }

  private func save() {
    var settings = stored
    settings.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
    if !token.isEmpty { settings.token = token }
    do {
      try environment.serverSettings.save(settings)
      stored = settings
      token = ""
      status = ServerConnection.untested.text
      saved(settings)
    } catch {
      status = "Could not save the token"
    }
  }

  private func test() async {
    guard stored.isConfigured else {
      status = ServerConnection.notConfigured.text
      return
    }
    let transport = environment.isUITest ? environment.vmTransport : stored.transport()
    status = await ServerConnection.check(transport).text
  }

  private func label(_ text: String) -> some View {
    Text(text).textStyle(.label).foregroundStyle(Theme.muted)
  }

  private func field(_ content: some View, id: String) -> some View {
    content
      .accessibilityIdentifier(id)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .padding(Theme.spaceMd)
      .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.surface))
      .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).strokeBorder(Theme.edge))
  }

  private func pill(_ title: String, id: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .foregroundStyle(Theme.onInvert)
        .padding(.horizontal, Theme.spaceCard)
        .frame(minHeight: Theme.sizeTarget)
        .background(Capsule().fill(Theme.invert))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
  }
}
