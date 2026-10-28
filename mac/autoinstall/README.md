# Auto-install Ingest on the iPhone from the Mac

A free Apple Personal Team signs an app for 7 days. After that Ingest stops opening, and its
background location and sync stop with it. `stezu_autoinstall.sh` fixes that from the MacBook: a
launchd agent rebuilds the app from `origin/main` and installs it on the iPhone over Wi-Fi every
morning, with hourly retries until it works. No paid Apple Developer Program, no TestFlight, no AI
(decision D-104).

Status: built and tested on Linux only, with stub `git`, `xcrun`, `xcodebuild`, `xcodegen`,
`osascript` and `security` (and under bash 3.2.57, the version of macOS's `/bin/bash`). It has not
run on a Mac. The devicectl JSON fields it reads come from Flutter's, Expo's and KeepAlive's
parsers, not from a capture on Isaac's Mac.

## What a run does

1. In its own clone, `~/Library/Application Support/Stezu/autoinstall/stezu-health` (never your
   working clone): `git fetch`, then `git reset --hard origin/main`. Nothing is edited there, so
   the reset loses nothing.
2. Decides. It installs when `origin/main` differs from the last installed commit, when the last
   successful install is 5 or more days old, when the installed profile expires within 2 days, or
   with `--force`. Otherwise it logs one line and exits 0. A commit that failed to build today is
   not rebuilt each hour; a new commit, the next day or `--force` tries again.
3. Finds the iPhone with `xcrun devicectl list devices --json-output`: the paired iPhone that
   CoreDevice can reach, or the one pinned with `STEZU_DEVICE_ID`. Not reachable (asleep, another
   network, eduroam) logs `phone not reachable, will retry` and exits 0. If the JSON does not have
   the expected shape, the run fails and says so; it does not guess.
4. Copies `Config/Local.xcconfig` (your signing team) from the working clone that install.sh
   recorded, runs `xcodegen generate`, deletes Xcode's cached provisioning profiles for
   `com.ik301.stezuhealth` and `com.ik301.stezuhealth.RestActivity` only, and builds:

       xcodebuild -project StezuHealth.xcodeproj -scheme StezuHealth -configuration Debug \
         -destination id=<udid> -derivedDataPath ~/Library/Application\ Support/Stezu/autoinstall/DerivedData \
         -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

   Deleting the cached profile matters: `-allowProvisioningUpdates` reuses a profile that is still
   valid, so without it a rebuild on day 5 would still expire on day 7. With it, Xcode asks Apple
   for a new 7-day profile with the Apple account signed in to Xcode.
5. Installs with `xcrun devicectl device install app --device <udid> .../Debug-iphoneos/StezuHealth.app`
   (the RestActivity Live Activity extension is inside it). The app's data on the phone is kept.
6. Only after the install succeeds, writes the commit, the time and the new profile's expiry to the
   state file, and posts a notification: "Ingest updated to abc1234". A failure posts "Ingest
   install failed: <reason>" and exits 1. If the phone stays out of reach while the signing has
   less than 36 hours left, one notification a day says so.

Flags: `--dry-run` (decide, find the iPhone, print the commands, build nothing), `--force`,
`--status` (last install, days until the 7-day expiry, whether the iPhone is reachable).

## Set up (on the Mac, once)

1. Xcode from the App Store, opened once. `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
   if `xcodebuild -version` complains about the Command Line Tools. `brew install xcodegen`.
2. Xcode > Settings > Accounts (Apple Accounts in newer Xcode): your Apple ID is signed in.
3. In your working clone, `scripts/set-team.sh` (README, "Build on your Mac"), then build and run
   Ingest on the iPhone once from Xcode with a cable. On the iPhone: Settings > Privacy & Security
   > Developer Mode on; Settings > General > VPN & Device Management > your Apple ID > Trust.
4. Wireless pairing:
   1. With the cable in and the iPhone unlocked, open Xcode > Window > Devices and Simulators.
   2. Select the iPhone and tick **Connect via network**.
   3. Unplug it. A network icon next to its name means Xcode reaches it over Wi-Fi.
   The iPhone must be unlocked (or recently unlocked) and on the same Wi-Fi as the Mac. Campus
   networks such as eduroam usually block the discovery between devices, so use home Wi-Fi, or
   join the Mac to the iPhone's Personal Hotspot.
5. From your working clone:

       mac/autoinstall/install.sh

   It checks for Xcode, xcodegen and git, makes the dedicated clone, records where your
   `Config/Local.xcconfig` is (if it is missing, it tells you to run `scripts/set-team.sh` first),
   copies the script to `~/Library/Application Support/Stezu/autoinstall/`, shows a `--dry-run`,
   loads the agent with `launchctl bootstrap gui/$UID`, and offers a first install right away.
   Say yes: if macOS asks whether `codesign` may use your signing key, click **Always Allow**, so
   later runs under launchd do not stall on that prompt.

Rerun `install.sh` after a change to `mac/autoinstall/` reaches your clone: launchd runs the copy.

Settings, `~/.config/stezu/autoinstall.env` (mode 0600, never in the repo):

    STEZU_LOCAL_XCCONFIG=<working clone>/Config/Local.xcconfig   # written by install.sh
    STEZU_DEVICE_ID=<UDID>                                        # optional: pin one iPhone

Pin the iPhone when more than one paired iPhone is reachable (the run fails and asks). The UDID is
in `xcrun devicectl list devices` or Xcode's Devices window. Never paste it into the repo.

## Schedule

`~/Library/LaunchAgents/com.ik301.stezu.autoinstall.plist` runs the script at 06:30 and on the hour
from 07:00 to 22:00. After a successful install the later runs only log a skip, so the hourly entries
are retries for mornings when the phone was out of reach or the build failed. A time missed while
the Mac slept runs once when it wakes. It does not run at load. PATH includes `/opt/homebrew/bin`
and `/usr/local/bin` for xcodegen.

To change the times, edit the `StartCalendarInterval` entries (`Hour`, `Minute`) in
`mac/autoinstall/com.ik301.stezu.autoinstall.plist` and rerun `install.sh`, or edit the installed
copy and reload it:

    launchctl bootout gui/$(id -u)/com.ik301.stezu.autoinstall
    launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.ik301.stezu.autoinstall.plist

The 5-day rule is `RENEW_AFTER_DAYS` in the script.

## Check that it works

    ~/Library/Application\ Support/Stezu/autoinstall/stezu_autoinstall.sh --status
    tail -n 5 ~/Library/Logs/Stezu/autoinstall/autoinstall.log      # one line per run
    ls -t ~/Library/Logs/Stezu/autoinstall/run-*.log | head -n 1    # the last build, in full
    launchctl print gui/$(id -u)/com.ik301.stezu.autoinstall | grep -E 'state|last exit'
    launchctl kickstart gui/$(id -u)/com.ik301.stezu.autoinstall    # run it now, as launchd does

Files: the state is `~/Library/Application Support/Stezu/autoinstall/state` (commit, install time,
profile expiry, device). Each build writes `~/Library/Logs/Stezu/autoinstall/run-<time>.log`; the
last 10 are kept. `launchd.out.log` and `launchd.err.log` there catch anything launchd itself saw.
DerivedData in the same folder takes a few GB.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `phone not reachable, will retry` every hour | Unlock the iPhone on the Mac's Wi-Fi. Check Xcode's Devices window shows it with a network icon; if not, plug in once and tick Connect via network again. On eduroam use home Wi-Fi or the iPhone's hotspot. |
| `not paired` or `no paired iPhone` | Do the wireless pairing steps above with the cable. |
| `Developer Mode is ... on <iPhone>` | iPhone: Settings > Privacy & Security > Developer Mode, then restart it. |
| `build failed: No Account for Team` or `requires a development team` | Sign in to Xcode > Settings > Accounts; check `Config/Local.xcconfig` in your working clone (`scripts/set-team.sh`) and rerun install.sh. |
| `build failed: ... maximum number of apps` or App ID limit | A free team allows only a few apps per device and new App IDs per week: delete an old sideloaded app from the phone, or wait. |
| The run hangs at codesign, or `errSecInternalComponent` | Run the script once from Terminal and click Always Allow on the keychain prompt. The login keychain must be unlocked (you are logged in). |
| `several paired iPhones are reachable` | Set `STEZU_DEVICE_ID=<udid>` in `~/.config/stezu/autoinstall.env`. |
| `devicectl JSON has no result.devices list` | An Xcode update changed the JSON. Compare `xcrun devicectl list devices --json-output /tmp/d.json` with `find_device` in the script and fix the parser. |
| `already failed to build today` | Fix main, or run with `--force` after fixing the local problem. |
| No notifications appear | They come from `osascript` (shown as Script Editor): allow it in System Settings > Notifications. |
| The app says Untrusted Developer | iPhone: Settings > General > VPN & Device Management > your Apple ID > Trust. |
| `--status` says the signing expires in under 2 days right after an install | Xcode reused an old profile. Check that the run log says it removed cached profiles; delete `~/Library/MobileDevice/Provisioning Profiles/*` and `~/Library/Developer/Xcode/UserData/Provisioning Profiles/*` for the app by hand if not. |

## Tests

    mac/autoinstall/run_tests.sh                                 # Linux or macOS
    BASH_UNDER_TEST=/bin/bash mac/autoinstall/run_tests.sh       # on the Mac: bash 3.2

`Tests/stubs/` holds fake `git`, `xcrun`, `xcodebuild`, `xcodegen`, `osascript` and `security`
put first on PATH, and `Tests/fixtures/` synthetic devicectl JSON (a Wi-Fi iPhone, an unreachable
one, two iPhones, a changed shape). They cover the skip, a new commit, the 5-day and expiring-profile
renewals, an unreachable or locked phone, build and install failures, the pinned device, the
launchd template and more. `scripts/gate-linux.sh` runs them as G8.

## Uninstall

    mac/autoinstall/uninstall.sh           # unload the agent and remove its plist
    mac/autoinstall/uninstall.sh --purge   # also the clone, DerivedData, state, logs and settings

Ingest stays on the iPhone until its current signing expires.

## Sources

- devicectl JSON shape (`result.devices[]`, `connectionProperties.pairingState`, `transportType`,
  `tunnelState` "unavailable" when out of reach, `hardwareProperties.udid`): Flutter
  `packages/flutter_tools/lib/src/ios/core_devices.dart` (BSD), Expo
  `packages/@expo/cli/src/start/platforms/ios/devicectl.ts` and `AppleDevice.ts` (MIT).
- Clearing the cached profile so a rebuild gets a fresh 7-day one, `-allowProvisioningDeviceRegistration`,
  and that Xcode 27 omits `reality` for physical devices: KeepAlive, github.com/oli-zr/keepalive
  (MIT). No code was copied.
