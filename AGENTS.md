# Agents

Read this first. SPEC.md says what to build (for v1, D-032 to D-035 override it where they differ), DESIGN.md how it looks, DECISIONS.md why. features.json is the work list, and each card works on exactly one entry.

## Layout

- Packages/StezuCore: pure Swift logic. No SwiftUI, UIKit or HealthKit imports and no `#if` platform branches; it builds and tests on Linux. Outside-world protocols live here with their fakes: `HealthStore`/`FakeHealthStore`, `VMTransport`/`FakeVMTransport`.
- App/Sources: the SwiftUI app (target StezuHealth, com.ik301.stezuhealth, iOS 17), one folder per area (Workout/, Food/, Data/), plus Health/HealthKitStore.swift.
- App/Shared: compiled into the app and the extension (RestActivityAttributes). App/RestActivity: the Live Activity widget extension (com.ik301.stezuhealth.RestActivity).
- App/Tests: AppTests (unit). App/UITests: AppUITests (XCUITest). Both run in the ios CI job only.
- project.yml: the XcodeGen spec (the .xcodeproj is generated and gitignored). App/StezuHealth.entitlements: HealthKit.
- scripts/: the gates. .github/workflows/ci.yml: CI. PROGRESS.md: the log.

## Build and test

    cd Packages/StezuCore && swift build && swift test        # Linux or macOS
    xcodegen generate && xcodebuild test -project StezuHealth.xcodeproj -scheme StezuHealth \
      -destination 'platform=iOS Simulator,name=<an installed iPhone>' CODE_SIGNING_ALLOWED=NO

The scheme runs AppTests and AppUITests. CI picks the simulator dynamically (see ci.yml).

## features.json (schema 2)

- `kind: engine`, F-001 to F-010: core logic judged by unit tests (`tests`).
- `kind: story`, S-001 on: something Isaac does in the app. `steps` are user actions and what the screen then shows; `tap_budget`; `depends_on` (earlier stories); `core_tests` (StezuCoreTests or AppTests names, may be empty); `ui_tests` (AppUITests names); `screenshots` (attachment names); `needs_server`; `passes`.
- `scripts/check-features.py --ready` lists the stories whose dependencies already pass.

## Story workflow

1. Branch wt/S-xxx. The story's steps are the acceptance test.
2. Write the core tests, then the UI test: one XCUITest class per story in App/UITests/<Class>.swift. It launches with `UITestApp.launch(...)`, performs every step by tapping accessibility ids, asserts what each step says the screen shows, and calls `saveScreenshot("<name>", of: app)` for every name in `screenshots`.
3. Build the screens. Give every control a test touches an accessibility id like `workout.logger.log`. Keep `home.card.<area>`, `screen.<area>.title` and `nav.home`; the smoke test uses them.
4. Keep to the tap budget. Missing data shows "--".
5. Flip with `scripts/check-features.py --flip S-xxx`. It needs every depends_on story passing, every listed test and screenshot name present, and the StezuCoreTests passing. The required `ios` check then runs AppTests and AppUITests on the PR and exports the screenshots. A story is done only when that check is green.

## -uitest fakes

`UITestApp.launch()` passes `-uitest`, and `AppEnvironment.fromLaunch()` then chooses an in-memory store (`StorageMode.memory`), `FakeHealthStore`, `FakeVMTransport` (routes in `UITestFixtures.vmRoutes`) and `FixturePhotoSource` (a plate drawn in code). Views read them from `@Environment(\.appEnvironment)`; never create HealthKit, URLSession or camera objects inside a view. Options: `-uitest-scenario <name>` seeds the synthetic data a story names (the first story to name a scenario creates it), `-uitest-offline` starts the fake transport offline, `-uitest-persist` keeps the store in a temp folder across a relaunch, and `-uitest-reset` empties it first. A story that needs another fake (barcode, file picker, Live Activity) adds it to AppEnvironment the same way.

## Server client contract

The VM server lives in server/ and is built separately; cards never touch server/. The app reaches it only through `VMTransport`: a method, a path relative to the base URL, and a body. The base URL and a bearer token are set once on the device in Settings (S-002); the token lives in the Keychain, and neither is ever committed. Until then the app uses `UnconfiguredVMTransport`, which throws `notConfigured`. Write one small client per endpoint that builds a `VMRequest` and decodes the reply; tests and `-uitest` use `FakeVMTransport`. Paths and JSON shapes are in server/README.md (GET /health, GET /menu, POST /scan, GET /search, GET /barcode/{gtin}); every call but /health needs the token. Stories with needs_server true are built against the fake now.

## Gates

Night cards use wt/F-xxx or wt/S-xxx, in a worktree under .worktrees/<id>/. infra/* branches are only for Isaac or a daytime session he starts. Run `scripts/gate-linux.sh` (FEATURE_ID overrides the branch name) before every push.

- G1: `swift build && swift test` in Packages/StezuCore.
- G2: `scripts/check-features.py --base origin/main`. On a card branch only the card's entry may change, and only its `passes`; passes:true needs its tests and screenshot names to exist. main and infra/*: schema only.
- G3: `scripts/diff-budget.sh origin/main`, counting uncommitted and untracked files. Card branches: at most 300 changed non-test lines in 12 files (*.md and Tests/ excluded), and no change to *.entitlements, project.yml, scripts/, .github/, Package.swift, Info.plist or *.xcodeproj. infra/* may change those and has no size limit. Every branch: no signing team, identity or profile in project.yml, and no test file loses a `func test`.
- G4: `swift format lint --strict` over all Swift files. Fix with `swift format -i -r <paths>`.
- G5: `server/run_tests.sh` when it exists; skipped with a notice otherwise.

CI: `linux-core` runs the gates; `ios` builds the app and the extension, runs AppTests and AppUITests on a simulator, and uploads the xcresult and the screenshots. Both checks are required to merge.

## Parallel cards

Several cards run at once. Before merging: `git fetch && git rebase origin/main`, rerun the gates, push. In DECISIONS.md, PROGRESS.md and features.json keep both sides of a conflict (in features.json, both `passes` flips). Renumber your decision records to the next free D-number on main. Prefer new files to edits of shared ones: one UI test class per story, one folder per area. Add to shared types (HealthStore, AppEnvironment, UITestFixtures) at the end, so a rebase can keep both sides.

## Rules

1. Stay inside the card's boundaries. Change only what the entry needs.
2. Never weaken or delete tests. Tests are XCTest, and every test method is named `func test...`.
3. Flip features.json only through `scripts/check-features.py --flip <id>`. Never edit `passes` by hand.
4. Append at most 3 decision records per card to DECISIONS.md, status proposed: Problem (without the solution); Given; Constraints, each with what it breaks; Options, 2 to 4; Decision; Evidence (files and commit); Reverse if.
5. Absent is not zero. Missing data is nil or an explicit absent state, shown as "--", never 0.
6. Every derived value carries a confidence.
7. No new dependencies, entitlements, capabilities, Info.plist keys or bundle IDs on a card branch. Those go in an infra/* PR after Isaac approves.
8. Update PROGRESS.md at the end of each card.

## Test names

Tests are listed as `Target.Class/testMethod`, for example `StezuCoreTests.TrendWeightTests/testFirstWeighInSeedsTrend` or `AppUITests.SmokeUITests/testLaunchShowsThreeCardsAndEachOpensItsArea`. Core tests live in Packages/StezuCore/Tests/StezuCoreTests, app tests in App/Tests, UI tests in App/UITests. Write listed tests with exactly those names.

## Public repo: no personal data, ever (D-034)

This repo is public. Never commit personal data of any kind: training programs, body stats, intake, health samples, hall preferences, IPs, hostnames, tokens or server URLs. Seeds and fixtures are generic and synthetic. Isaac's own program and settings are imported on the device from a private file.
