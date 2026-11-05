# Widget auth on a free Personal Team

Status: proposed, 2026-11-05 (spike t_26280da8, D-152). Device check pending: see "What is not verified yet".

The home-screen widgets (word of the day, goal, tasks) run in an app extension, a separate process with its own sandbox. That process can't read the app's Keychain items or its UserDefaults unless the entitlements allow it. It needs two things from the app: the server address and the bearer token that Settings saves (D-043).

## Decision

Recommended: Keychain sharing. Put the widgets in the existing RestActivity extension and give that extension the app's own keychain access group.

- The app keeps its entitlements as they are. It already stores the token in its default access group, which is its app ID (`<TeamID>.com.ik301.stezuhealth`), because it declares no `keychain-access-groups`.
- The extension declares `keychain-access-groups = [$(AppIdentifierPrefix)com.ik301.stezuhealth]`. Apple's keychain docs say an app or extension can join another app's default group this way, and that a query without `kSecAttrAccessGroup` "matches any of your app's groups". So the widget reads the token with the same query the app uses (service `com.ik301.stezuhealth.server`, account `token`) and gets the existing item. Isaac re-enters nothing and the token is not migrated.
- The address is in the app's `UserDefaults.standard`, which the extension can't read. The app also writes it as a second Keychain item (same service, account `address`) when Settings saves, and once at launch if that item is missing.
- The widgets go into `RestActivityBundle` next to the Live Activity. One WidgetKit extension can hold both. That means no new target, bundle ID, App ID or profile, and no change to the D-104 autoinstall job, which already clears profiles for both bundle IDs and fails if `RestActivity.appex` is missing.

Fallback, used if the device check below fails: a widget-only read token, scoped on the server to the surface route and injected at build time from the gitignored `Config/Local.xcconfig`. Details are in the fallback section below.

Not chosen: App Groups. Apple lists them as available to free accounts, but they add an App Group ID registered with Apple, and they only help if the token goes into shared UserDefaults or a shared file, which puts it in plaintext (D-043 rejected UserDefaults for the token). The widget can keep its offline cache in its own container, so it needs nothing from a shared one. Add an App Group only if the app ever has to hand data to the widget.

## Answers to the spike's questions

| Question | Answer | Source |
|---|---|---|
| Can a Personal Team add an app extension? | Yes. RestActivity, a WidgetKit extension, signed with his free team and ran on his iPhone. | D-047 device test, 2026-10-25 |
| (a) App Groups on a free team? | Listed as available ("Apple Developer" column). Not used. | Apple, Supported capabilities (iOS), read 2026-11-05 |
| (b) Keychain sharing on a free team? | Listed as available. A keychain group needs no registration with Apple; the profile's team wildcard (`<TeamID>.*`) should cover it. Not yet checked on the device. | Same table; Apple, "Sharing access to keychain items among a collection of apps" |
| Does an extension count against free-team limits? | Each extension bundle ID is its own App ID, and a free account can register only 10 App IDs per rolling 7 days. A new widget target would use one; reusing RestActivity uses none. The 3-active-apps-per-device limit counts apps. Whether extensions count toward it isn't documented, and reuse sidesteps the question. | AltStore docs "App IDs" and "Activating Apps"; Xcode's "maximum App ID limit" error |
| Push, CloudKit, Family Controls? | Not available on a free team. The widgets need none of them. | Same Apple table |

## Config changes for the infra card (t_b9bf9287)

Recommended path. This diff was applied to a copy of main at 9548f90. `plutil -lint` and Python's `plistlib` and `yaml` all parsed the result (output under Evidence).

New file `App/RestActivity.entitlements`, beside `App/StezuHealth.entitlements` and outside the extension's source folder, so XcodeGen never treats it as a source:

```diff
+<?xml version="1.0" encoding="UTF-8"?>
+<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
+<plist version="1.0">
+<dict>
+	<key>keychain-access-groups</key>
+	<array>
+		<string>$(AppIdentifierPrefix)com.ik301.stezuhealth</string>
+	</array>
+</dict>
+</plist>
```

`project.yml`, RestActivity target:

```diff
@@ -77,6 +77,7 @@ targets:
     settings:
       base:
         PRODUCT_BUNDLE_IDENTIFIER: com.ik301.stezuhealth.RestActivity
+        CODE_SIGN_ENTITLEMENTS: App/RestActivity.entitlements
         INFOPLIST_FILE: App/RestActivity/Info.plist
         GENERATE_INFOPLIST_FILE: YES
         INFOPLIST_KEY_CFBundleDisplayName: Ingest Rest
```

No other config changes:

- `App/StezuHealth.entitlements`: unchanged. Adding a `keychain-access-groups` entry with a different first value would change the app's default group and strand the saved token.
- `App/RestActivity/Info.plist`: unchanged. Home-screen widgets use the same `com.apple.widgetkit-extension` point as the Live Activity.
- `Config/Signing.xcconfig`: unchanged. It already signs both targets.
- `mac/autoinstall`: unchanged (`BUNDLE_IDS` and the `PlugIns/RestActivity.appex` check already cover this).
- No App Transport Security exception, because the server is HTTPS through `tailscale serve`.

Code the infra card needs besides config:

- A small Keychain reader in `App/Shared` (compiled into both targets) that runs the existing token query plus the new `address` item. `DeviceServerSettingsStore` keeps writing and also saves `address`.
- At launch, the app writes the `address` item if UserDefaults has an address and the Keychain doesn't, so the current install works without re-saving Settings.
- After Settings saves, the app calls `WidgetCenter.shared.reloadAllTimelines()`.
- The widget never caches the token. It reads it on every timeline reload, so a token changed in Settings takes effect at the next reload.

If Isaac wants a separate widget extension instead of reusing RestActivity, the extra cost is a new target (`com.ik301.stezuhealth.Widgets`) with its own `configFiles` pointing at `Config/Signing.xcconfig`, the same entitlements file, a `dependencies` entry on the app, one more App ID, and the autoinstall's `BUNDLE_IDS` and extension check (card t_bdade94e).

## Fallback: widget-only read token

Use this if the device check fails, for example if signing rejects the extension's `keychain-access-groups` or the widget's request reaches the server without a token.

- Server (t_9a7130f7 already structures auth for this): a second env var `STEZU_WIDGET_TOKENS` on the VM. The surface route accepts a device token or a widget token; every other route keeps accepting device tokens only. A leaked widget token can read the surface payload and nothing else.
- Provisioning, with nothing committed: generate the token on the VM and add it to the server's env file. Then write a 0600 file holding two xcconfig lines, `STEZU_WIDGET_TOKEN = ...` and `STEZU_SERVER_URL = https:/$()/<host>:<port>` (the `$()` stops xcconfig from reading `//` as a comment). Isaac copies it with `scp` and appends it to his working clone's `Config/Local.xcconfig`. That file is gitignored, and the autoinstall copies it into its own clone on every run.
- Extension: two keys in `App/RestActivity/Info.plist`, `StezuWidgetToken = $(STEZU_WIDGET_TOKEN)` and `StezuServerURL = $(STEZU_SERVER_URL)`, read through `Bundle.main`. The committed file names the variables only.
- `scripts/set-team.sh` overwrites `Local.xcconfig` (`cat >`), so the fallback also changes it to keep lines other than `DEVELOPMENT_TEAM`.
- Limits: the token sits in plaintext in the built `.appex` on the Mac (DerivedData) and on the phone, so the server-side scope is the real protection. Rotating it takes an edit on the Mac and a rebuild (the autoinstall picks it up within a day). The phone can't change it.

## Limits of the recommended approach

- The widget can't refresh or rotate the token. It doesn't need to, because device tokens are static server-side and don't expire. If the server revokes the token, the widget gets 401 and shows its cached payload (or "--") until Isaac saves a new token in Settings.
- The widget holds the full device token, write routes included. It is the same token, on the same phone, read by code from the same repo, so this adds no new holder. Move to the scoped token if that changes.
- The item is `AfterFirstUnlockThisDeviceOnly`. After a reboot and before the first unlock, the read fails and the widget shows its cache. The item isn't in backups, so a new phone needs the token entered again (already true for the app).
- Every widget request goes over Tailscale like the app's. With the VPN off, fetches fail and the widget shows its cache.
- WidgetKit decides when timelines reload, roughly 40 to 70 reloads a day. "Once a day" and "every 30 to 60 minutes" are requests, not guarantees.
- The widget stops when the 7-day free signing lapses, together with the app. D-104 renews both.
- CI builds unsigned (`CODE_SIGNING_ALLOWED=NO`), so it can't catch an entitlement or provisioning failure. Only a device build can.
- If the signing Apple ID changes, the team prefix changes and the app and the widget both lose the saved token. Enter it again in Settings.

## Evidence

Verified:

- A WidgetKit extension signs and runs on his free team: D-047 (RestActivity, 2026-10-25).
- Apple's capability table (developer.apple.com/help/account/reference/supported-capabilities-ios, read 2026-11-05) ticks App groups, Keychain sharing, HealthKit and Background modes for "Apple Developer" (free), and leaves Push notifications and iCloud unticked. The HealthKit tick matches the D-047 device result.
- Apple's keychain doc quotes: "If you don't specify any keychain access groups, then the app ID is the default." "If you don't specify an access group in the query, the search matches any of your app's groups."
- The app's current token item has no `kSecAttrAccessGroup` and is `AfterFirstUnlockThisDeviceOnly` (`App/Sources/Settings/ServerSettings.swift`). `App/StezuHealth.entitlements` declares no keychain groups.
- The config diff above, applied to main at 9548f90:

```
App/RestActivity.entitlements: OK
App/StezuHealth.entitlements: OK
yaml ok; RestActivity entitlements = App/RestActivity.entitlements
plistlib: {'keychain-access-groups': ['$(AppIdentifierPrefix)com.ik301.stezuhealth']}
```

What is not verified yet: a signed device build with the new entitlement. The spike ran on the VM. The Mac didn't answer on 2026-11-05 (`ssh` over Tailscale timed out and `tailscale ping` got no reply), and CI can't sign. The device check is the first step of the infra card, before any widget code:

1. Apply the two changes above, then `xcodegen generate` and Cmd+R to the phone. Pass: both targets sign. Fail: an error that the profile doesn't include `keychain-access-groups`. Then switch to the fallback.
2. On the Mac, confirm what got signed. Don't paste the team ID anywhere public; report yes or no.

   ```
   APP=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 6 -path '*Debug-iphoneos/StezuHealth.app' | head -1)
   codesign -d --entitlements - --xml "$APP/PlugIns/RestActivity.appex" | plutil -p -
   security cms -D -i "$APP/PlugIns/RestActivity.appex/embedded.mobileprovision" | plutil -extract Entitlements.keychain-access-groups xml1 -o - -
   ```

   Pass: the first command shows `keychain-access-groups` with `<TeamID>.com.ik301.stezuhealth`, and the second shows `<TeamID>.*`.
3. Add the placeholder widget and let it make one authenticated request (`/surface/today` once it is deployed, `/sync/status` before). On the VM: `journalctl --user -u stezu-server | grep -E 'GET /(surface|sync/status)'`. A 200 at that time means the widget read the token. A 401 means it sent no token or a wrong one, so switch to the fallback. No request at all means a network problem (Tailscale), not auth.

## Reverse if

- Step 1 or 3 of the device check fails: use the fallback.
- The app needs to give the widget data it already has, such as a prefetched payload: add an App Group then.
- Isaac buys the paid Developer Program: nothing here changes, though TestFlight would replace D-104.
