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

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Settings")
        .font(.system(size: 34, weight: .semibold))
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
      HStack(spacing: 12) {
        pill("Save", id: "settings.save", action: save)
        pill("Test connection", id: "settings.test") { Task { await test() } }
      }
      Text(status)
        .font(.system(size: Theme.subtitleSize))
        .accessibilityIdentifier("settings.status")
      Spacer(minLength: 0)
    }
    .foregroundStyle(Theme.text)
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Theme.background.ignoresSafeArea())
    .onAppear {
      stored = environment.serverSettings.load()
      address = stored.address
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
    Text(text).font(.system(size: Theme.labelSize)).foregroundStyle(Theme.label)
  }

  private func field(_ content: some View, id: String) -> some View {
    content
      .accessibilityIdentifier(id)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .padding(12)
      .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.card))
      .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.cardBorder))
  }

  private func pill(_ title: String, id: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .foregroundStyle(Theme.invertedText)
        .padding(.horizontal, 18)
        .frame(minHeight: 44)
        .background(Capsule().fill(Theme.invertedCard))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
  }
}
