# Progress

Newest entry first. One entry per card: the date, the card, what changed, the gate result and what comes next.

## 2026-10-25 S-012 Food opens the camera; the shutter saves the photo first (night agent)

- FoodView is now the camera: the image fills the screen (the fixture plate in `-uitest`, `CameraPreview` over `LiveCameraPhotoSource` on the phone), Home at the top left, a Photo/Barcode pill switch (`food.mode.photo` / `food.mode.barcode`, value on/off), the shutter (`food.shutter`) and History (`food.history`). The bottom circles from S-001 stay.
- Camera access is asked when Food opens (`PhotoSource.authorize()`, true for sources without a camera). If denied, the screen says to turn it on in Settings and offers an Open Settings button.
- The shutter saves the photo through `MealCapture.shutter()` into `MealCaptureStore` (files per meal, D-044) and opens a sheet with "Matching..." and "Photo saved on this phone." No network call is made.
- `AppEnvironment.live()` now uses `LiveCameraPhotoSource`, so AppEnvironmentTests/testNoArgumentSelectsLiveServices asserts that type instead of `NoCameraPhotoSource` (same check, new live type).
- Tests: AppTests.MealCaptureTests (2: the listed test, plus a disk store found again by a new instance) and AppUITests.FoodCameraUITests/testFoodOpensCameraAndShutterSavesPhoto (screenshots s012-camera, s012-captured). Gates: `FEATURE_ID=S-012 scripts/gate-linux.sh` passed G1 to G5 (diff 295 of 300 lines). Flipped with check-features.py --flip S-012.
- Left undone: History does nothing yet (no history story built); Barcode mode only hides the shutter until the barcode story; "Matching..." never finishes until S-013 sends the saved meal to POST /scan. The denied state is not covered by a UI test (the simulator cannot be made to deny in-process). `NoCameraPhotoSource` is no longer used by the app.

## 2026-10-25 S-002 Server address and token in Settings (night agent)

- Added App/Sources/Settings/: `ServerSettings` (address, token, `baseURL`, `isConfigured`, masked token, `transport()`), `DeviceServerSettingsStore` (address in UserDefaults, token in the Keychain, this device only), `MemoryServerSettingsStore` (`-uitest`), `ServerConnection` (GET /health outcome and its display text) and `URLSessionVMTransport` (bearer token on every call). SettingsView opens as a sheet from a gear on Home (`home.settings`); Save stores both and calls `AppEnvironment.useServer`, which swaps the live transport (D-043). `UITestFixtures.vmRoutes` answers GET /health.
- Tests: AppTests.ServerSettingsTests (live transport through a stub URLProtocol, unconfigured cases), AppUITests.ServerSettingsUITests/testSaveServerAndTestConnection (screenshots s002-settings-empty, s002-settings-connected). Synthetic address and token only.
- Gates: `FEATURE_ID=S-002 scripts/gate-linux.sh` G1 to G5 PASS locally, 294 non-test lines in 7 files. Flipped with check-features.py --flip.
- Naming: ids `settings.address`, `settings.token`, `settings.token.saved`, `settings.save`, `settings.test`, `settings.status`, `screen.settings.title`. No library added (Foundation, Security).
- Left undone / noticed: no server feature exists yet, so "Set up the server in Settings" shows only in Settings; later Food cards should map `VMTransportError.notConfigured` through `ServerConnection.notConfigured.text`. An address typed without a scheme gets https; a plain-http tailnet address may need an ATS exception (Info.plist, infra only). Settings has no close button (swipe down); the token cannot be cleared from the UI once saved.

## 2026-10-25 S-003 Workout templates and Start (night agent)

- Added `TemplateExercise`, `WorkoutTemplate`, `WorkoutSeed` and `TemplateLibrary` (upsert by key, edit, rotation `next(after:)`) in Packages/StezuCore/Sources/StezuCore/WorkoutTemplate.swift. The generic 5-day seed (Push, Pull, Legs, Upper, Lower; seedVersion 1) is App/Sources/Workout/PrebuiltWorkouts.json. `WorkoutTemplateStore` loads the library file and applies a newer seed at launch. Decision D-042.
- Workout screen: the next template as the black card with its exercises and Start, "Sessions this week" and "Working sets" as "--", and a row for each other template and Empty workout. Start (or a row) opens `WorkoutLoggerView` on the first exercise: name, "Set 1 of N", rep range.
- Tests: WorkoutTemplateTests (3, core), WorkoutTemplateStoreTests (2, AppTests: the seed ships in the bundle, edits survive a newer seed), WorkoutStartUITests (screenshots s003-workout-today, s003-logger-first-set). Gates: `FEATURE_ID=S-003 scripts/gate-linux.sh` passed G1 to G5 (296 non-test lines before the flip). S-003 flipped with check-features.py --flip.
- Naming: ids `workout.today.{name,start,exercise.N}`, `workout.template.<key>`, `workout.week.{sessions,sets}`, `workout.logger.{exercise,set,reps}`. No library added.
- Left undone (diff budget): the seed sits in App/Sources/Workout, not App/Resources, because App/Resources is not a source path in project.yml (infra PR if it should move). No sessions are stored, so the rotation always starts at Day 1 and the week numbers are always "--"; S-004/S-008 add sessions. The logger has no way back to the template list except the bottom nav; logging, steppers and Finish come with S-004 and S-008. No weight step per exercise in the seed yet (S-004 says default 5 lb).

## 2026-10-25 S-001 Bottom circles switch areas (night agent)

- Added App/Sources/BottomNav.swift: three 58 pt circles (Data, Food, Workout), the active one black, ids `nav.circle.<area>` with accessibility value active/inactive. AppShell attaches it under every area screen with `safeAreaInset` and owns the area switch (D-041). Area views and AreaScaffold are unchanged; `Area.title` added.
- Tests: AppUITests.ShellNavigationUITests/testBottomCirclesSwitchAreas walks the story (Home "--" cards, Workout, Food, Data, Home) and saves s001-home, s001-workout, s001-food, s001-data.
- Gates: `FEATURE_ID=S-001 scripts/gate-linux.sh` passed G1 to G5. Flipped with check-features.py --flip S-001.
- Left undone: none for the story. The circles show their names as text; DESIGN.md does not say icon or text.

## 2026-10-25 infra/v1-stories: project infrastructure and the stories ledger (daytime session)

- Why: the first night's 8 cards passed every gate, yet the phone showed three blank cards that could not be tapped. features.json described engineering units, and nothing checked screens.
- Project (project.yml): App/StezuHealth.entitlements (HealthKit) through CODE_SIGN_ENTITLEMENTS; Info.plist keys NSHealthShareUsageDescription, NSHealthUpdateUsageDescription, NSCameraUsageDescription and NSSupportsLiveActivities; a RestActivity widget extension (com.ik301.stezuhealth.RestActivity) with a minimal ActivityKit Live Activity and RestActivityAttributes in App/Shared; an AppUITests target. The scheme runs AppTests and AppUITests.
- App: `-uitest` switches AppEnvironment to an in-memory store, FakeHealthStore, FakeVMTransport and a fixture photo (D-039). Home cards are buttons that open placeholder Data, Food and Workout screens with a Home button; the bottom circles are S-001. Core gained `HealthStore`/`FakeHealthStore` and `VMTransport`/`FakeVMTransport`/`UnconfiguredVMTransport`; the app gained `HealthKitStore` with the v1 read and write types.
- Tests: a smoke UI test (three cards, open each area, keepAlways screenshots), AppEnvironmentTests (4), VMTransportTests (3), FakeHealthStoreTests (1).
- Ledger: features.json schema 2. F-001 to F-010 unchanged as engine entries; S-001 to S-026 stories (D-038). `check-features.py --ready` lists what can start.
- Gates: G2 understands stories and lets infra/* restructure the ledger; G3 keeps project files off card branches and allows them on infra/* (D-040); G5 runs server/run_tests.sh when it exists. CI's ios job runs unit and UI tests and uploads the xcresult and exported screenshots; ios is now required next to linux-core.
- Decision numbers: D-038 to D-040, because D-036 and D-037 are the server's on main.
- Next: S-001 (bottom nav), then S-002, S-003, S-012 and S-020 in parallel. S-021 reuses F-006 and F-007's test names, so those engine entries can be flipped (with --approved, D-033) once S-021 passes.

## 2026-10-25 Food server on the VM (server agent)

- Added server/: a FastAPI service with a SQLite cache, run as a systemd user service bound to the tailnet address only. Endpoints: `/health`, `/menu` (FoodPro, all 13 halls, cached per date, closed halls listed as unavailable), `/scan` (Claude vision against every hall's items for the meal, ranges, idempotent on meal_id plus photo hash), `/search` (dining fuzzy match, Open Food Facts, USDA FDC, text estimate) and `/barcode/{gtin}` (Open Food Facts). Contract in server/README.md. Decisions D-036 and D-037.
- Tests: server/run_tests.sh runs pytest offline with sockets blocked, on a saved FoodPro page, saved OFF and USDA responses and a fake model.
- Landed as four PRs to stay inside the G3 budget.
- Left undone / noticed: F-010's `DiningMenuClient` decodes a per-hall envelope with camelCase item keys; `/menu` returns all halls in one response with snake_case keys, so the app transport or the core decoder needs a small mapping. `/log` and `/sync` from report 09 section 7 are not built.

## 2026-10-25 F-005 Home screen three cards from a view model (night agent)

- Added `HomeViewModel` and `HomeInputs` in App/Sources/HomeViewModel.swift. Inputs are the optional core results: `TrendEstimate`, `WeeklyTargetDecision`, today's intake kcal, `ProteinFloor.Outcome` and `LastSessionNumbers`. Cards: Data (trend lb, 1 decimal), Food ("intake / target" kcal, subtitle adds "protein low" when under the floor), Workout (heaviest last-session set as "110 x 3", bodyweight as "N reps", subtitle "exercise, Nd ago"). `HomeCard` gained an optional `confidence`. Decision D-031.
- The inverted card comes from an injected `now` closure and a start-hour schedule (default 5 Data, 11 Food, 16 Workout, 20 Food). HomeView renders the model's cards with the existing Theme tokens inside a minute `TimelineView`. `HomePlaceholder.cards` now comes from the model with empty inputs.
- Tests: HomeViewModelTests (3 tests, synthetic values, built through the real core functions). Linux cannot build the SwiftUI app, so the view model and tests were also compiled and run in a scratch Swift 6 package on Linux (3/3 pass); the ios CI job runs them for real. Gates: `FEATURE_ID=F-005 scripts/gate-linux.sh` passed G1 to G4. F-005 flipped with check-features.py --flip.
- Left undone / noticed: nothing feeds `HomeInputs` yet; the app still shows all "--" until HealthKit import and storage land. The default schedule hours are guesses (D-010 puts the weigh-in at the gym, so a morning Data card may be wrong). Number text uses `String(format:)`, not the device locale, so no thousands separators.
- Next: F-006 or whichever card wires HealthKit into the inputs.

## 2026-10-25 F-009 Double-progression rule (night agent)

- Added `DoubleProgression` in Packages/StezuCore/Sources/StezuCore/DoubleProgression.swift: `Config` (rep range, default 8...12, and weight step, default 5 lb; failable init rejects a range below 1 rep or a non-positive step), `Action` (`.addReps` / `.addWeight`), `Suggestion` (pounds, per-set target reps, confidence) and `suggest(after:config:)` over F-008's `LastSessionNumbers`. Decision D-030.
- Working sets are the sets at last session's heaviest weight. All at or above the top: add one step, reset reps to the bottom. Otherwise one more rep per set below the top. No last session gives nil. Bodyweight stays nil pounds, never 0.
- Tests: DoubleProgressionTests (3 tests, synthetic numbers). Gates: `FEATURE_ID=F-009 scripts/gate-linux.sh` passed G1 to G4 locally. F-009 flipped with check-features.py --flip.
- Naming: `DoubleProgression.suggest(after:config:)`; no library added (Foundation only).
- Left undone / noticed: rep range and step are per call, not per exercise; per-exercise settings need a settings store. A bodyweight exercise at the top suggests adding one step of load, which may not suit every movement. A session where reps dropped sharply (a bad day) still only gets "add reps"; there is no deload rule.

## 2026-10-25 F-003 Weekly calorie target rule (night agent)

- Added `WeeklyTarget.evaluate(asOf:currentTarget:weighIns:lastChange:config:)` with `WeeklyTargetConfig` and `WeeklyTargetDecision` (action raise / lower / hold / alreadyChangedThisWeek / insufficientData, previous and new target, optional trend rate, reason, confidence) in Packages/StezuCore/Sources/StezuCore/WeeklyTarget.swift. It reuses `TrendWeight.estimate` for the trend today and 21 days ago.
- Rate = trend change over 21 days / 3. Raise by the configured step (default 100, band 100 to 150) when more than 0.15 lb/week under the 0.35 target; lower by 100 when more than 0.25 over. Under 21 days of data or under 4 weigh-ins in the last 7 days gives insufficient data and no change. Decisions D-028, D-029.
- Tests: WeeklyTargetTests (5 tests, synthetic weights and targets). Gates: `FEATURE_ID=F-003 scripts/gate-linux.sh` passed G1 to G4 locally. F-003 flipped with check-features.py --flip.
- Naming: `WeeklyTarget.evaluate`, `WeeklyTargetDecision.Action`; no library added (Foundation only).
- Left undone / noticed: the app has to store the target and the last change day (D-028); nothing does yet. The rule does not use F-002 expenditure; SPEC's rule is trend-only. With the default alpha 0.1 the trend lags about 9 days, so the 3-week rate reacts slowly; worth checking on real data. Reasons are English strings built in core.
- Next: the next open feature in features.json.

## 2026-10-25 F-008 Workout session model and rest timer (night agent)

- Added `WorkoutSession` (exercises and sets in log order) with a one-call `logSet(_:pounds:reps:at:)`, plus `WorkoutSet`, `ExerciseLog`, `LastSessionNumbers`, `WorkoutHistoryConfig` and `WorkoutHistory.lastSession(of:before:in:)` / `lastSessions(before:in:)` in WorkoutSession.swift. `RestTimer` in RestTimer.swift reads time from an injected `now` closure. Decisions D-026, D-027.
- Absent, not zero: a bodyweight set has `pounds == nil`; logSet rejects reps below 1 and weights that are 0, negative or not finite (returns nil, changes nothing); no earlier session gives nil; an idle timer has nil remaining.
- Tests: WorkoutSessionTests (2), RestTimerTests (1), synthetic numbers. Gates: `FEATURE_ID=F-008 scripts/gate-linux.sh` passed G1 to G4 locally. F-008 flipped with check-features.py --flip.
- Naming: exercises are identified by their exact name string; no library added (Foundation only).
- Left undone / noticed: no persistence for sessions yet (no store feature exists). Weight is pounds only, matching F-001. Rest-end notifications in the background would need the app layer (D-027).

## 2026-10-25 F-002 Expenditure estimate (night agent)

- Added `Expenditure.estimate(asOf:intake:weighIns:config:)` with `IntakeEntry`, `ExpenditureConfig`, `ExpenditureEstimate` and `ExpenditureResult` in Packages/StezuCore/Sources/StezuCore/Expenditure.swift. It reuses `TrendWeight.estimate` for the trend at both window edges.
- Expenditure = mean of full intake days - trend change x 3500 / 21. Partial days (under 50% of their 7-day block's median) are excluded and counted. Fewer than 14 full days, or no weigh-in by the day before the window, gives `.insufficientData(reason:)`, never 0. Decisions D-024, D-025.
- Tests: ExpenditureTests (3 tests, synthetic values). Gates: `FEATURE_ID=F-002 scripts/gate-linux.sh` passed G1 to G4 locally. F-002 flipped with check-features.py --flip.
- Naming: `Expenditure.estimate`, result enum `ExpenditureResult`; no library added (Foundation only).
- Left undone / noticed: the 14 and 18 full-day bars are guesses and need checking against real logging. A day logged in two separate apps would be summed twice; deduplication belongs to the HealthKit import. `ExpenditureConfig.windowDays` under 1 is not validated.
- Next: F-003, weekly calorie target rule.

## 2026-10-25 F-004 Protein floor flag (night agent)

- Added `ProteinFloor` in Packages/StezuCore/Sources/StezuCore/ProteinFloor.swift: `Meal` (protein low/high grams), `Config` (floor with no default, calendar, 3-day window, meals-per-day bar for high confidence), and `check(asOf:meals:config:)` returning `.evaluated(Check)` or `.insufficientData(Insufficient)`.
- The flag compares the mean of daily low-end sums over the read day and the 2 days before it with the floor; a mean exactly on the floor is not flagged. Any day in the window without a valid meal gives insufficient data. Decisions D-022, D-023.
- Tests: ProteinFloorTests (3 tests, synthetic grams and floor). Gates: `FEATURE_ID=F-004 scripts/gate-linux.sh` passed G1 to G4 locally. F-004 flipped with check-features.py --flip.
- Naming: all types nest under `ProteinFloor` (`Outcome`, not `Result`, to avoid shadowing Swift.Result) so they cannot collide with meal types other cards add tonight. No library added.
- Left undone / noticed: there is no shared meal type yet; when meal logging lands, map it onto `ProteinFloor.Meal` or merge the two. The floor value itself must come from device settings, which do not exist yet.
- Next: F-005 maps the result onto the Food card.

## 2026-10-25 F-010 Dining menu models and client (night agent)

- Added Packages/StezuCore/Sources/StezuCore/DiningMenu.swift: Codable `DiningMenu`, `DiningMeal`, `DiningMenuItem` (nutrition per serving, all optional), `DiningMenuResult` (`.available` / `.unavailable(reason:)`), and `DiningMenuClient` over an async `DiningMenuTransport` protocol. Decisions D-020 and D-021.
- The client sends an abstract `DiningMenuRequest` (hall, date). 404, `"status": "unavailable"` and a menu with no items all come back as `.unavailable`; other statuses and bad JSON throw `DiningMenuError`. Missing nutrition is nil, never 0.
- Tests: DiningMenuTests (3 tests, synthetic inline JSON fixture, fake actor transport, no network). Gates: `FEATURE_ID=F-010 scripts/gate-linux.sh` passed G1 to G4 locally.
- Not flipped: F-010 has needs_approval, so `passes` stays false until Isaac approves.
- Naming: `DiningMenuClient.menu(hall:date:)` and `DiningMenuClient.decode(_:)`; no library added (Foundation only).
- Left undone, waiting on Isaac: the endpoint URL, path and query shape, token storage and headers, and the real URLSession transport in the app. The JSON envelope in D-021 is this card's proposal; the VM endpoint has to serve it (or the decoder changes). Dates are plain "yyyy-MM-dd" strings, not validated. Menu values carry no confidence because they are source data, not derived; nutrition from FoodPro may need one once it feeds intake.
- Next: approval of F-010 step 4.

## 2026-10-25 F-001 Trend weight EWMA (night agent)

- Added `TrendWeight` (series and estimate), `WeighIn`, `TrendPoint`, `TrendEstimate`, `TrendWeightConfig` in Packages/StezuCore/Sources/StezuCore/TrendWeight.swift, and a shared `Confidence` type (level plus reason) in Confidence.swift for later features to reuse.
- Gap of d calendar days gives the new reading 1 - (1 - alpha)^d; alpha defaults to 0.1. Same-day readings are averaged; readings of 0, negative or NaN are dropped. Decisions D-017 to D-019.
- Tests: TrendWeightTests (4 tests, synthetic weights). Gates: `FEATURE_ID=F-001 scripts/gate-linux.sh` passed G1 to G4 locally. F-001 flipped with check-features.py --flip.
- Naming: `TrendWeight.series` / `TrendWeight.estimate(asOf:)`; no library added (Foundation only).
- Left undone / noticed: no explicit daylight-saving test (the code uses calendar day differences, D-018). `TrendWeightConfig` defaults to `Calendar.current`, so the app should pass the user's calendar explicitly once settings exist. `precondition` traps on an alpha outside (0, 1]; a config UI should validate first.
- Next: F-002, expenditure estimate.

## 2026-10-25 Scaffold

- Added SPEC.md, DESIGN.md, AGENTS.md (CLAUDE.md links to it) and features.json with F-001 to F-010, none passing.
- StezuCore holds a placeholder `StezuCore.version` with one test. The app holds a placeholder HomeView with one AppTests test.
- Gates G1 to G4 live in scripts/gate-linux.sh. CI runs linux-core (required) and ios (advisory).
- Verified: scripts/gate-linux.sh passes on main and from a wt/F-xxx worktree, and rejects a hand flip, a flip of another card's feature, a non-passes field edit, a removed test, an over-budget diff, signing keys and entitlements files. The first CI run on main was green in both jobs (ios used Xcode 26.6 and an iPhone 17 Pro simulator on iOS 26.5). Branch protection on main requires linux-core.
- Next: F-001, trend weight EWMA over irregular gaps.
