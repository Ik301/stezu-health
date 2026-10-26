# Progress

Newest entry first. One entry per card: the date, the card, what changed, the gate result and what comes next.

## 2026-10-25 Server: POST /sync and GET /sync/status (server/sync)

- Added server/stezu_server/health.py: a separate SQLite database (`STEZU_HEALTH_DB`, default `~/.local/share/stezu/health.db`, 0600, WAL) with samples, records and batches tables, and read-only views for Hermes: live_samples, daily_quantity, steps_by_source, daily_steps, sleep_by_source, sleep_nights, body_mass, heart_rate_daily, resting_hr, hrv, spo2, respiratory_rate, temperature, workouts, stezu_records. `POST /sync` and `GET /sync/status` in app.py; contract in server/README.md. Decision D-053.
- Tests: server/Tests/test_sync.py (10 tests: auth, replay, deletion tombstones, records, rejected items, the 5,000-item limit and speed, gzip, the views, file mode and time zone). `server/run_tests.sh` passes.
- Unblocks S-028 and S-029, which build against FakeVMTransport.
- Left undone: the views pick the largest single source per day for steps and sleep; Health's own source priority is not available to the server.

## 2026-10-25 S-011 Import a workout program file (night agent)

- Workout has an Import program row under the templates. Live it opens the Files picker for a .json file; `-uitest` uses a fixture picker on AppEnvironment that returns a generic two-template program (replaces Day 1, adds Day 6), or a broken one under `-uitest-scenario program-invalid`. The screen shows "Imported N templates" or "Import failed." with the reason. Decision D-052.
- Core: `ProgramImport.parse` and `TemplateLibrary.importProgram` (ProgramImportTests, 2 tests). App: ProgramFilePickerTests. UI: ProgramImportUITests (valid import, then a relaunch with the invalid file), screenshot s011-imported.
- Gates: `FEATURE_ID=S-011 scripts/gate-linux.sh` passed G1 to G5 (168 non-test lines in 5 files). S-011 flipped with check-features.py --flip.
- Naming: `ProgramFilePicker` (.files / .fixture); no library added (UniformTypeIdentifiers is a system framework).
- Left undone / noticed: an import never removes templates missing from the file; the result line stays until the screen is left; there is no undo.

## 2026-10-25 S-006 Rest countdown after each set, with a Live Activity (night agent)

- `RestTimer` gained `adjust(by:)`, `skip()` and `endsAt`; adjusting keeps the start time. App/Sources/Workout/RestActivityController.swift holds the rest for the logger plus the `RestAlerts` protocol and `FakeRestAlerts`; LiveRestAlerts.swift drives the RestActivity Live Activity and one local notification at zero. `AppEnvironment.restAlerts` is live on the phone and the fake in `-uitest`. Decision D-052.
- Logger screen: Log starts a rest card at the logged exercise's template rest (no tap), with the countdown (`workout.rest.countdown`, value = start time), `workout.rest.minus`, `workout.rest.plus` and `workout.rest.skip`. At zero or on Skip the card goes away and the activity ends.
- Tests: RestTimerTests/testAdjustKeepsStartTime, testSkipEndsRest (core), AppTests.RestActivityControllerTests, AppUITests.RestTimerUITests (screenshots s006-rest-running, s006-rest-adjusted). Gates: `FEATURE_ID=S-006 scripts/gate-linux.sh` G1 to G5 PASS. Flipped with check-features.py --flip S-006.
- Step 4: answered by Isaac's device check (D-047): the RestActivity extension signed with his free personal team and installed on his iPhone. Whether this card's Live Activity actually appears on his lock screen is still to see in the walkthrough. Neither the Live Activity nor the notification can be seen in the simulator UI test; only the fake's calls are tested.
- Left undone: the rest lives in the logger view, so leaving Workout or relaunching drops the in-app countdown (the Live Activity and notification stay until they end). Undo does not cancel a running rest. The notification permission is asked at the first logged set.

## 2026-10-25 S-005 Last session's numbers, same template first (night agent)

- Added `TemplateHistory.lastSession(of:template:before:in:)` and `lastSessions(for:before:in:)` in Packages/StezuCore/Sources/StezuCore/TemplateHistory.swift, plus `LastSessionNumbers.summary(setAt:)` ("Last 60 x 8, 7d ago", "Last BW x 12, today"). `WorkoutSession` gained an optional `templateKey`; `Confidence` and `LastSessionNumbers` are Codable. `SetLogger` takes `history`, keeps `last` per exercise and prefills each exercise from its last session's first set. Decision D-046.
- Logger screen: the Log card shows `workout.logger.last` (or "Last --"); each logged row adds the last session's numbers for that set. `AppEnvironment.workoutHistory` feeds it; `UITestFixtures.workoutHistory(scenario:)` seeds "workout-history" (Day 1 7 days ago, a newer Day 2 with bench and the only overhead press; synthetic numbers).
- Tests: TemplateHistoryTests (3, core), WorkoutHistoryFixtureTests (1, AppTests), LastSessionUITests (screenshots s005-last-numbers, s005-first-ever). Gates: `FEATURE_ID=S-005 scripts/gate-linux.sh` G1 to G5 PASS, 163 non-test lines in 8 files. Flipped with check-features.py --flip S-005.
- Left undone: the live app has no stored history (no Finish yet, S-008), so last numbers only appear under the scenario. The rotation still starts at Day 1 because it does not read history. After a set is logged the card keeps that set's numbers (S-004) rather than switching to the last session's next set.

## 2026-10-25 S-004 Log a set, steppers, bodyweight, undo (night agent)

- Added `SetLogger` in Packages/StezuCore/Sources/StezuCore/SetLogger.swift: the prepared set (weight, reps, bodyweight flag), `log(at:)`, `undo()`, `stepWeight(up:)`, `stepReps(up:)`, `toggleBodyweight()`; after an exercise's last set the card moves to the next exercise. `WorkoutSession` and its sets are now Codable and gained `removeLastSet(of:)`. `TemplateExercise` gained optional `weightStep` and `startPounds`; the seed (seedVersion 2) gives barbell lifts a 45 lb empty-bar start. Decision D-045.
- Logger screen: the black Log card with exercise, "Set k of N", rep range, weight and reps between - and + buttons (no keyboard), a BW toggle and Log; logged sets of the exercise below with Undo. `WorkoutSessionStore` writes active-workout.json after every change.
- Tests: SetLoggerTests (3, core), WorkoutSessionStoreTests (1, AppTests), SetLoggerUITests (screenshots s004-prefilled, s004-logged, s004-undone). Gates: `FEATURE_ID=S-004 scripts/gate-linux.sh` passed G1 to G5 (285 non-test lines before the flip). S-004 flipped with check-features.py --flip.
- Naming: ids `workout.logger.{weight,repCount,log,undo,bodyweight}`, `workout.logger.{weight,repCount}.{plus,minus}`, `workout.logger.logged.N`. `workout.logger.reps` stays the rep range (S-003's test reads it).
- Left undone: the saved workout is never loaded back, so a relaunch starts fresh (resume belongs with S-008 or later). No exercise in the seed sets its own `weightStep` yet, so every step is 5 lb. Logged rows show only the current exercise's sets. No way to jump between exercises other than finishing their sets.

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

## 2026-10-25 S-013 Photo matched against every hall's menu (night agent)

- After the shutter saves the photo (S-012), `MealMatcher` downscales it to at most 1000 px, hashes it (SHA-256, CryptoKit), and `PhotoMatchClient` (core) sends POST /scan with the meal id, the service day, the meal period from the capture time (`MealPeriod.at`: breakfast before 10:30, lunch before 16:00, dinner after) and mode `dining`. The sheet goes from "Matching..." to the item list: name, hall (or "Not on a menu"), servings, kcal and protein ranges, a "rough" badge for unlisted or rough items, and meal totals as ranges. Any failure shows "Could not match" with the photo still saved.
- Core: FoodRange.swift (range, `total`), PhotoMatch.swift (`MealPeriod`, `MatchedItem`, `PhotoMatch`, `PhotoMatchClient`). FakeVMTransport gained held routes. Decisions D-049, D-050.
- Tests: PhotoMatchClientTests (4), FoodRangeTests (2), AppTests PhotoMatchSheetTests (2), AppUITests PhotoMatchUITests (screenshot s013-matched). `FEATURE_ID=S-013 scripts/gate-linux.sh` passed G1 to G5 locally (295 non-test lines before the flip). S-013 flipped with check-features.py --flip.
- Naming: core fields mirror the server's keys via convertFromSnakeCase (`itemId`, `proteinG`); no library added.
- Left undone: no retry queue for failed or offline scans (the photo stays saved, nothing resends it); no depth regions are sent; item confidence is decoded but not shown; alternates are ignored; the meal-period cutoffs are guesses and use the device time zone, not New York; a failed scan has no UI test.

## 2026-10-25 S-020 Connect Apple Health once, then Sources (night agent)

- First open of Data shows what Stezu reads and writes and one Connect Apple Health button; nothing is asked at launch. Connect calls `HealthStore.requestAuthorization` once (`HealthConnection`, flag in UserDefaults; memory in -uitest), then Data opens to the overview every time. Overview has a Sources button; the weekly rows come with S-021/S-022 ("Weekly rows: --").
- Sources (sheet): one row per v1 `HealthType`: "Present" or "--", last sample date, sample count over the last 7 days with per-app counts (so a strap's body-mass samples show apart from Stezu's), the denied-read hint for absent types, and a "Not in Health" list (empty: nothing writes yet).
- Core: HealthSources.swift (`HealthType`, `HealthSample`, `HealthTypeSummary` with confidence, `HealthSources.summarize/load`); `HealthStore` gained `samples(of:since:)` and `latestSampleDate(of:)`, in FakeHealthStore (synthetic samples) and HealthKitStore (HKSampleQuery, source name and bundle id). Decision D-054.
- Tests: HealthSourcesTests (2), AppTests HealthConnectTests (1), AppUITests HealthConnectUITests (screenshots s020-connect, s020-overview-empty, s020-sources). `FEATURE_ID=S-020 scripts/gate-linux.sh` passed G1 to G5 (290 non-test lines before the flip).
- Left undone: nothing records failed writes yet, so "Not in Health" always says None (the write stories should feed `SourcesView.failedWrites`). Strap types (S-027) are not in `HealthType` yet. The 7-day heart-rate query fetches every sample; with a strap that may be slow, and a statistics query would be cheaper. The flag does not re-ask when new types are added (see D-054 Reverse if).

## 2026-10-25 S-007 Swap an exercise from the library, or add a custom one (night agent)

- The Log card's exercise has a menu (an ellipsis) with Swap. It opens the Exercises library as a sheet: a search field (case-insensitive name match), New exercise, and the list grouped by muscle, each row showing when it was last done ("today", "7d ago", "--" if never) from the history plus this session. A tap swaps the exercise into the card's slot for this session only (sets and reps from the slot, rest from the library, prefill from its last session or "--"); the template is unchanged.
- New exercise: name, equipment, muscle, rest seconds (number pad), Save. It gets the key "custom-<name slug>" (-2, -3 on a clash), is marked Custom in its row, the search switches to it, and it can be picked. Custom exercises are saved to custom-exercises.json; the bundled list is App/Sources/Workout/ExerciseLibrary.json (the 25 template exercises plus dumbbell fly, generic). Decision D-055.
- Tests: ExerciseLibraryTests (3, core), ExerciseLibraryStoreTests (2, AppTests), ExerciseLibraryUITests (2; screenshots s007-library, s007-swapped, s007-custom). `FEATURE_ID=S-007 scripts/gate-linux.sh` passed G1 to G5 (294 non-test lines before the flip). S-007 flipped with check-features.py --flip.
- Naming: `ExerciseLibrary`, `LibraryExercise`, `SetLogger.swap(to:history:)`, `TemplateExercise.replaced(by:)`; no library added.
- Left undone: the tap budget says 2 taps to swap but the steps (menu, then Swap, then pick) take 3; equipment is stored but not shown in rows (diff budget); custom exercises cannot be edited or deleted; in -uitest (memory storage) a custom exercise is gone once the sheet closes; undo after swapping a slot that already had sets returns the card to the swapped exercise.

## 2026-10-25 S-008 Finish saves the workout and writes it to Apple Health (night agent)

- The logger has a Finish button (`workout.logger.finish`, no confirmation). It ends any rest, closes the logger and clears active-workout.json. `WorkoutFinish.finish` discards a session with no sets; otherwise it writes through `HealthStore.saveStrengthWorkout(start:end:externalID:)` and keeps the session either way, with `inHealth` true or false. Finished sessions live in finished-workouts.json (`FinishedWorkoutStore`).
- The Workout screen shows this week's (Monday to Sunday) sessions and working sets, "--" with none, and one row per session with "In Health" or "Not in Health". `HealthKitStore` builds a traditional strength training workout with HKWorkoutBuilder, no energy samples, tagged with `HKMetadataKeyExternalUUID`, and skips the write when that id is already in Health. FakeHealthStore records writes and can be set to fail. Decision D-056.
- Tests: WorkoutFinishTests (3), AppTests FinishedWorkoutStoreTests (1), AppUITests WorkoutFinishUITests (screenshots s008-finished, s008-in-health). `FEATURE_ID=S-008 scripts/gate-linux.sh` passed G1 to G5 locally (242 non-test lines in 7 files). S-008 flipped with check-features.py --flip.
- Left undone: no retry of a "Not in Health" session; the session is stored after the Health write returns, so a kill during the write loses it; every logged set counts as a working set (no warm-ups yet); the rotation still starts at the first template (finished sessions do not advance it); the failed-write row has no UI test (core test only); the real HealthKit write is unchecked until a device run; a "Not in Health" session does not yet feed S-020's `SourcesView.failedWrites`.
## 2026-10-25 S-021 This week's weight trend and one-tap weigh-in (night agent)

- The Data overview now has a Weight row for the Monday-to-Sunday week: trend (lb), the trend's change this week, weigh-in days "n of 7", the confidence reason, and "From:" the apps the trend uses. Weigh in opens a sheet with a stepper prefilled with the last weigh-in in 0.1 lb steps (no keyboard); Save writes one body-mass sample and the row reloads. A week with no weigh-ins shows "--" everywhere.
- Only samples Health credits to Stezu (com.ik301.stezuhealth) count as weigh-ins, so a strap's profile weight never moves the trend; Sources (S-020) already lists other body-mass apps with counts. Decision D-057.
- Core: WeeklyWeight.swift (`WeekWeight`, `WeeklyWeight.week/prefill/weighIn/load`); `HealthSample` gained `value` (pounds for body mass); `HealthStore` gained `saveBodyMass(pounds:at:)` in FakeHealthStore and HealthKitStore (HKQuantitySample in pounds; reads now carry body-mass values). AppEnvironment gained `now` (pinned to a synthetic Sunday in `-uitest-scenario data-week`, which also starts connected and seeds synthetic weigh-ins plus one strap sample).
- Tests: HealthStoreTests (2), WeighInTests (2), AppUITests WeightUITests (screenshots s021-weight, s021-weigh-in). `FEATURE_ID=S-021 scripts/gate-linux.sh` passed G1 to G5 (259 non-test lines in 9 files before the flip).
- Left undone: no setting to accept weigh-ins from another app (a smart scale); a failed Health write is silent (it should feed Sources' "Not in Health"); the 150 lb stepper start when Health has no body mass at all is a generic default; the trend reads 90 days of history only.

## 2026-10-25 S-022 This week's steps, sleep, HRV and resting heart rate with coverage (night agent)

- The Data overview has a second card under Weight: Steps (mean per day over days with data, "n of 7 days"), Sleep (mean time asleep, "n of 7 nights", labelled context), HRV (median ms, "n samples", labelled context) and Resting HR (mean, "n of 7 days"). A metric without data shows "--" beside its coverage, and the card then shows the Sources hint (no data or read access off).
- Steps and resting heart rate come from one HKStatisticsCollectionQuery per type in day buckets (sum, discrete average), so Health merges overlapping apps. Sleep nights are built from sleepAnalysis stages: in bed and awake do not count, overlapping asleep stages count once, a night is dated by the day it ends. Decision D-058.
- Core: WeeklyHealth.swift (`WeeklyStat` with confidence, `SleepStage`, `SleepInterval`, `SleepNights.nights`, `WeeklyStats.week/meanPerDay/median/sleep`, `WeeklyHealth.load`). `HealthStore` gained `dailyValues(of:in:)` and `sleepIntervals(since:)`; HealthKitStore reads quantity values in each type's unit (ms, count/min, count). `-uitest-scenario data-week` adds synthetic steps, HRV, resting HR and 5 nights of stages.
- Tests: WeeklyStatTests (2), SleepNightTests (1), AppUITests WeeklyHealthUITests (screenshot s022-health-rows). `FEATURE_ID=S-022 scripts/gate-linux.sh`: see the PR (298 non-test lines in 7 files before the flip).
- Left undone: Sources does not list sleep for the fake (FakeHealthStore keeps sleep apart from samples); the 18:00 night cutoff and confidence tiers (5+ high, 3+ medium) are defaults, not settings; HRV reads raw samples, so a strap writing many readings a night would weigh that night more; the overview is not scrollable, so on a small phone the cards may be squeezed.

## 2026-10-25 S-024 Tap a metric to see its last 8 weeks, then tap a week to see its days (night agent)

- Each overview row (Weight, Steps, Sleep, HRV, Resting HR) has a chevron (`data.<metric>.open`) that opens one detail sheet for every metric: the last 8 Monday-to-Sunday weeks, newest first, each with its value and coverage ("n of 7 days", "n of 7 nights", "n samples" for HRV), then "From:" the apps and a note on how the value is made. Weight adds a chart of weigh-in dots and the trend line. Tapping a week lists its days Monday to Sunday; a day without data shows "--". "8 weeks" goes back, Done closes.
- Core: MetricHistory.swift (`Metric`, `MetricDay`, `MetricWeek`, `MetricHistory.history/load`). Weight's week value is the trend at that week's last Stezu weigh-in. Decision D-060.
- Tests: MetricHistoryTests (1), AppUITests MetricDetailUITests (screenshots s024-metric, s024-week-days). `FEATURE_ID=S-024 scripts/gate-linux.sh` passed G1 to G5 (294 non-test lines in 5 files before the flip). S-024 flipped with check-features.py --flip.
- Naming: `Metric` (core enum, raw values match the overview ids), `MetricOpenButton`, `TrendChart` drawn with Canvas (no Charts import).
- Left undone: only the chevron opens a detail, not a tap anywhere on the row (the rows keep their child accessibility ids, and a whole-row button would merge them); sleep shows "From: --" because `SleepInterval` carries no source; the chart has no axis labels; value formatting is duplicated between WeeklyHealthRows and `Metric.format` (diff budget); steps' source names come from a raw sample read over 8 weeks, which may be slow on a device with many samples.

## 2026-10-25 S-009 Resume a workout after closing the app (night agent)

- A workout in progress already lived in active-workout.json (S-004). Now, when the Workout screen loads with no logger open, `SessionResume.atLaunch` reads it: within 3 hours of its last set (a default in `SessionResumeConfig`) the black card becomes a Resume card (template name, "n sets logged", Resume), and one tap reopens the saved logger unchanged: same exercise, sets, undo and swaps. Past 3 hours a session with sets is finished through `WorkoutFinish` ending at its last set (it shows in the week and goes to Health); one with no sets is dropped. Starting another workout while Resume is shown finishes the saved one first. Decision D-064.
- Tests: SessionResumeTests (2, core), AppUITests SessionResumeUITests (screenshots s009-resume-card, s009-resumed). `FEATURE_ID=S-009 scripts/gate-linux.sh` passed G1 to G5 locally (126 non-test lines in 3 files before the docs). S-009 flipped with check-features.py --flip.
- Naming: `SessionResume` (`.nothing`, `.resume`, `.close`), `SessionResume.lastSet(of:)`; no library added.
- Left undone: the idle check runs when the Workout screen loads, not at app launch or on return from the background, so a session closed by idle time reaches Health only once Workout is opened; the rest countdown is not saved, so a resumed logger shows no rest; the idle close has no UI test (core test only); no AppTests test covers `loadSaved`.

## 2026-10-25 S-010 Weekly workout history and past sessions (night agent)

- Workout has a History row under the week's numbers. It opens a sheet (NavigationStack): Monday-to-Sunday weeks that have a session, newest first, each headed "Mon, <date> - Sun, <date>" with its working-set count, then its sessions newest first ("<template>   <day>   n sets"). A session opens its exercises with sets as weight x reps ("65 x 5", bodyweight "BW x 10"); an exercise opens every session that has it, newest first. Sources: the seeded `workoutHistory` plus finished sessions (S-008). Decision D-061.
- Core: WeeklyHistory.swift (`HistoryWeek`, `WeeklyHistory.weeks/sessions(with:in:)`, `WorkoutSession.workingSets`).
- Tests: WeeklyHistoryTests (3), AppUITests WorkoutHistoryUITests (screenshots s010-history, s010-session). `FEATURE_ID=S-010 scripts/gate-linux.sh` passed G1 to G5 (201 non-test lines in 3 files before the flip). S-010 flipped with check-features.py --flip.
- Left undone: the workout-history fixture's two sessions never leave an empty week between them (and the fixture test pins its two keys), so the no-empty-week rule is covered by the core test only; the UI test works out from today's weekday whether the two sessions share a week. Working-set counts carry no confidence (every logged set counts, no warm-ups yet). No editing or deleting of past sessions; no In Health status inside History.

## 2026-10-25 S-027 This week's blood oxygen, respiratory rate and temperature from the strap (night agent)

- The S-022 card gained three rows, each labelled context: Blood oxygen (weekly median %, "n samples"), Respiratory rate (weekly median br/min, "n of 7 nights") and Temperature (weekly median °F, "n of 7 nights"). No samples shows "--" beside the coverage, and the card shows the Sources hint. The overview now scrolls.
- HealthType gained oxygenSaturation, respiratoryRate, bodyTemperature and wristTemperature; all four are in the HealthKit read set (the one Connect sheet) and on Sources, whose "Last 7 days" line now has an id and counts from the scenario's clock. Temperature uses wrist temperature only when no body temperature exists that week. Decision D-062.
- Core: `WeeklyStats.median(_:in:scale:)` and `nightlyMedian`, `WeeklyHealth.bloodOxygen/respiratoryRate/temperature`. `-uitest-scenario data-week` adds synthetic strap readings (UITestFixtures.strapSamples).
- Tests: WeeklyStatTests/testMedianOfPercentReadings, AppUITests WeeklyHealthUITests/testStrapContextRowsShowCoverage (screenshot s027-strap-rows). `FEATURE_ID=S-027 scripts/gate-linux.sh` passed G1 to G5 (140 non-test lines in 8 files before the docs).
- Left undone: the three strap rows have no 8-week detail chevron (S-024's `Metric` covers only the earlier rows; the merge with S-024 shows the chevron only where a `Metric` exists); temperature is shown in °F with no unit setting; Apple's sleeping wrist temperature is read as an absolute value, not a deviation from baseline; the real HealthKit reads for the new types are unchecked until a device run.

## 2026-10-25 S-017 Offline meal photo waits in a queue and matches later (night agent)

- A shutter press with no connection (or no server set) shows "Pending, will match when online" and "Today: -- kcal, +1 pending" in the sheet, never 0 kcal. The photo was already saved; a meal stays pending until its POST /scan reply is saved beside it as `<id>.scan`. Opening Food retries pending meals oldest first; the newest one matched opens in the sheet with its items and ranges. Nothing deletes a queued meal. Decision D-063.
- Core: MealQueue.swift (`QueuedMeal`, `MealQueue.retry/pendingCount/todayText`); `PhotoMatchClient.scanReply` returns the raw reply. App: `MatchState.pending`, `MealMatcher.scan/retryQueue`, `MealCaptureStore.saveReply/queue`.
- Tests: MealQueueTests (3), AppTests MealQueueStoreTests (1), AppUITests OfflineQueueUITests (screenshots s017-pending, s017-matched-later).
- Left undone: the "+1 pending" line is in the pending sheet only, not on Home's Food card; retries run only when Food opens (not at launch or on reconnect); there is no Log button yet (S-015), so a matched meal is "ready to Log" but logged kcal stays "--"; no list of queued meals (History is still a stub).

## 2026-10-25 S-014 Search dining items, restaurants and packaged food from the camera screen (night agent)

- The camera screen has a search bar under the top bar. Typing (300 ms debounce) sends GET /search with the text, today's date and the meal period, and a panel over the camera lists Dining halls (each dish with every hall and its serving), Restaurants and generic (USDA) and Packaged food (brand and label serving), with kcal ranges. A tap opens the item list sheet (S-013's `PhotoMatchSheet`) with that item at 1 serving. "Estimate from text" sends the same call with estimate=true and opens the item list with the rough item and its wider range.
- Core: FoodSearch.swift (`FoodSearchSource`, `FoodSearchGroup`, `FoodSearchClient.search/estimate/decode`); `MatchedItem` gained `brand`, `PhotoMatch` a public init; FakeVMTransport matches a route narrowed by one query pair. Decisions D-065, D-066.
- Tests: FoodSearchClientTests (2), AppTests FoodSearchPanelTests (1), AppUITests FoodSearchUITests (screenshots s014-results, s014-text-estimate). `FEATURE_ID=S-014 scripts/gate-linux.sh` passed G1 to G5 (291 non-test lines in 7 files before the flip). S-014 flipped with check-features.py --flip.
- Naming: groups keep the server's source names (`dining`, `open_food_facts`, `usda_fdc`, `estimate`); no library added.
- Left undone (diff budget): no clear button on the search bar (delete the text to return to the camera); the server has no restaurant source, so "restaurants" are USDA FoodData Central results plus the text estimate; a packaged food with only per-100 g values shows "--" (no per-100 g or per-package choice); a pick is not saved as a meal yet (S-015 adds Log); the panel has no offline or error UI test; results are not cached on the phone.
## 2026-10-25 S-028 Health data copies itself to Hermes on the VM; Settings shows the last sync (night agent)

- Settings has a Hermes sync row ("--" before the first sync, then the time and the server's sample count, plus "n waiting" while batches are queued) and a Sync now button (`settings.sync.status`, `settings.sync.now`).
- `HealthSync` (core actor) reads each v1 Health type in pages of 2,000 from its anchor (`HealthStore.changes`; the first read starts 90 days back), queues each page with a new batch id, saves the queue and the anchor together in sync-state.json, then sends POST /sync in order. Batches leave the queue only on a 2xx. Offline, unconfigured or a 5xx stops the pass and the batch waits for the next one, which resends it with the same batch id. Deletions go in `deleted`. Then GET /sync/status gives `samples_total`; only a 200 there sets the sync time. Decision D-067.
- `HealthKitStore.changes` uses HKAnchoredObjectQueryDescriptor with archived anchors. Quantities go in fixed units through the shared `HealthType.unit` (lb, count, count/min, ms, kcal, g; S-022's units plus kcal and g for the two dietary types), sleep as its raw category value, workouts with a null value and activity type, duration and active energy in metadata. Only numeric HealthKit metadata is kept.
- Triggers: open and every return to the foreground (scenePhase active), and after Finish, each detached at utility priority. Health is read only once connected (S-020); `-uitest` counts the fake as connected and syncs only on Sync now. `-uitest-scenario sync` seeds three synthetic heart-rate readings, and the fake status answers `samples_total: 3`.
- Tests: HealthSyncTests (3), AppUITests HermesSyncUITests (screenshot s028-sync-row). `FEATURE_ID=S-028 scripts/gate-linux.sh` passed G1 to G5 (289 of 300 non-test lines with the flip). S-028 flipped with check-features.py --flip.
- Left undone (diff budget): Stezu's own records are not sent yet. There is no `records` array, no `SyncRecord` model, and no workout_session or set records from finished-workouts.json. Workouts written to Health still arrive as HKWorkout samples, but their sets do not. S-029 (meal records) needs the same model, so it should add `SyncRecord` to `SyncBatch` and the queue; workout and set records can then reuse it.
- Also left undone: a 400 or 413 batch stays at the head of the queue for good (no drop-and-log); string and date HealthKit metadata are dropped; `activity_name` and `total_distance_m` are not sent; the first backfill runs in the foreground pass with no background task, so iOS may suspend a long one (the next pass resumes from the saved anchor); the real HKAnchoredObjectQueryDescriptor path has not run on a device yet; the row shows the phone's sync time, not the server's `devices[].last_batch_at`.
- Seen on CI, not fixed here: `ExerciseLibraryUITests.testAddCustomExercise` (S-007) failed once on this PR with "Neither element nor any descendant has keyboard focus" on `workout.library.custom.rest`, while main's runs of the same test pass; it looks like a keyboard-focus flake in that test (typing before the field has focus).

## 2026-10-26 S-015 Fix the item list and log the meal with one Log tap (night agent)

- The item list sheet (after a photo or a search pick) is now `MealEditor`: tap an item's name to search inside the sheet and replace it (the replacement keeps the servings), - and + step servings by 0.5 and never below 0.5, Remove takes an item out, + Add item searches and appends the pick at 1 serving. Totals are summed from the edited items after every change. The single Log button saves the meal as confirmed (`<id>.log` beside the photos), closes the sheet to the camera and shows "Meal logged" with Undo for 8 seconds; Undo deletes the file. Decision D-068.
- Core: MealEdit.swift (`MatchedItem.withServings`, `MealEdit.step/replace/remove/add`, `LoggedMeal`); `FoodRange` and `MatchedItem` are now Codable. App: `MealEditor`, `PhotoMatchSheet.row` takes a name action and controls, `MealCaptureStore.log/unlog/logged`, the undo toast in `FoodView`.
- Tests: MealEditTests (3), AppTests MealLogStoreTests (1), AppUITests MealEditUITests (screenshots s015-edited, s015-logged). `FEATURE_ID=S-015 scripts/gate-linux.sh` passed G1 to G5 (293 non-test lines in 7 files before the flip). S-015 flipped with check-features.py --flip.
- Naming: ids `food.match.item.N.{plus,minus,remove}`, `food.edit.{add,log}`, `food.edit.search.{field,cancel}`, `food.logged.{toast,undo}`, `food.log.error`.
- Left undone (diff budget): logged meals are not read anywhere yet, so today's line and Home's Food card still show "--" kcal; nothing sends logged meals to the server (/sync); the sheet opens at half height and search raises it to full height (it stays there after the pick); the name tap is a tap gesture on the text, not a Button; Undo does not reopen the sheet; Undo has no UI test (AppTests covers the file); an item with no servings count is stepped as if it were 1 serving.

## 2026-10-26 S-023 This week's food ranges and workouts on Data (night agent)

- Data's overview has a third card under the health rows. Food: "logged n of 7 days", the mean kcal and the mean protein per logged day as ranges ("1000-1320 kcal", "52-68 g protein"), "--" with no meals. Workouts: "n this week" and one line per session, newest first ("Sat  Example Watch" or "Mon  3 sets") with its source (Stezu or Health); "--" with none. Sources: logged meals (`MealCaptureStore.logged()` plus a scenario's `mealHistory`), Stezu sessions (seeded `workoutHistory` plus finished-workouts.json) and Health's workouts. Decision D-069.
- Core: WeeklyIntake.swift (`WeeklyRange`, `WeeklyFood`, `WeekWorkout`, `WeeklyIntake.food/workouts`). `HealthKitStore` now dates workouts by their start (other samples keep their end).
- `-uitest-scenario data-food-week`: data-week's connection and Sunday clock with synthetic logged meals on 5 days, two Stezu sessions, Finish's Health copy of one and a watch workout.
- Tests: WeeklyStatTests/testRangeMeanOverLoggedDays and testWorkoutsMergeSourcesWithoutDuplicates, AppUITests WeeklyFoodWorkoutUITests (screenshot s023-food-workouts). `FEATURE_ID=S-023 scripts/gate-linux.sh` passed G1 to G5 (227 non-test lines in 7 files before the docs). S-023 flipped with check-features.py --flip.
- Left undone: the Food and Workouts rows have no 8-week detail (S-024's `Metric` does not cover them); Health's own dietary energy and protein samples are not read, only meals logged in Stezu; Health workouts show the writing app's name, not the activity type or duration; the rows load once when Data opens, so a meal logged meanwhile appears on the next open; Home's Food card still shows "--".

## 2026-10-26 S-025 Open a day and see everything recorded on it (night agent)

- In a metric's week, each day has a chevron (`metric.day.N.open`); one tap opens the Day view inside the same sheet, titled with the date ("Week" goes back). It lists, in this order: weigh-ins from any app, logged meals with their items and kcal/protein ranges, workouts (Stezu sessions with every set; Health workouts that are not Finish's copy of a session), the night ending that day, each HRV reading and the day's steps. Each row says "From Stezu", or "From <app>, read-only" for Health's; a day with nothing shows "--". Decision D-070.
- Stezu's weigh-ins, meals and sessions have Delete (the first tap turns it into Confirm); meals also have Edit, which opens S-015's `MealEditor` and rewrites the meal's `.log` with the same id. Weigh-ins are deleted from Health through the new `HealthStore.deleteBodyMass(at:)` (HealthKit: only this app's samples at that instant); meals with `MealCaptureStore.unlog`; sessions by rewriting finished-workouts.json.
- Core: DayRecords.swift (`DayRecord`, `DayRecord.Kind/Owner`, `DayRecords.load`). App: Data/DayView.swift, MetricDetailView's day chevron and day state. `-uitest-scenario data-food-week` now also carries data-week's weigh-ins, steps, HRV, resting HR and sleep, so its Monday has every kind of record.
- Tests: DayRecordsTests/testDayGathersRecordsWithSources, AppUITests DayViewUITests (screenshot s025-day). `FEATURE_ID=S-025 scripts/gate-linux.sh` passed G1 to G5 (279 non-test lines in 6 files before the docs). S-025 flipped with check-features.py --flip.
- Naming: ids `day.record.N` (kind), `.detail`, `.source`, `.edit`, `.delete`, `day.empty`, `metric.day.back`.
- Left undone (diff budget): weigh-ins and sessions cannot be edited, only deleted; deleting a session leaves Finish's copy in Health (it then shows as a read-only Health workout); a failed Health delete keeps the record with no message; resting heart rate, blood oxygen, respiratory rate and temperature are not listed; sleep says "From Health" because sleep reads carry no app; Health workouts show "--" for their detail (no activity type or duration is read); only the chevron opens a day, not the whole row; Data's overview rows do not refresh after a delete or edit until Data reopens.

## 2026-10-26 S-016 Switch to Barcode, scan a package, and get it from Open Food Facts (night agent)

- One tap on the camera's pill switches to Barcode: the shutter goes, a frame and "Point the camera at a barcode" show, and the photo session hands the camera to VisionKit's DataScanner (EAN-8 and EAN-13, which covers UPC-A). A new code of 8 to 14 digits goes to GET /barcode/{gtin}; a product opens the item list at 1 serving with its brand, serving label and kcal and protein ranges, ready to Log. An unknown code shows "Not found" with "Search instead", which goes back to Photo mode and focuses the search bar. A server error shows "Could not look up the code" with the same button. Decision D-071.
- Core: Barcode.swift (`BarcodeLookup`, `BarcodeClient.lookup/decode/isGTIN`); `FoodSearchClient.Result` is now internal so the barcode reply decodes the same way. App: BarcodeScanner.swift (`BarcodeSource`, `BarcodeState`, `BarcodeStatusView`, `BarcodeScannerView`), FoodView's Barcode mode, `AppEnvironment.barcodeSource`, fixture routes and `-uitest-scenario barcode-unknown`.
- Tests: BarcodeClientTests (2), AppUITests BarcodeUITests (screenshots s016-barcode-mode, s016-product). `FEATURE_ID=S-016 scripts/gate-linux.sh` passed G1 to G5 (220 non-test lines in 6 files before the flip). S-016 flipped with check-features.py --flip.
- Naming: ids `food.barcode.status`, `food.barcode.search`; no library added (VisionKit and Vision are system frameworks).
- Left undone: a product with only per-100 g or per-package values shows "--" (no unit choice); UPC-E codes are not recognized; the same code scanned again while it stays in view is not looked up again until it leaves the frame; the live DataScanner path and the camera handoff have not run on a device yet (the simulator has no scanner); the "Could not look up" state has no UI test (core test only); offline shows the same message, with no queue for codes.

## 2026-10-26 S-018 A logged meal is written to Apple Health as one food entry (night agent)

- The Log tap now saves the meal on the phone, then writes it to Health as one HKCorrelation of type food holding dietary energy and protein: the meal totals' midpoints, each sample with its low and high in metadata (`stezu_kcal_low/high`, `stezu_protein_g_low/high`), the meal id as the correlation's sync identifier. The meal is saved again with `inHealth`, and the "Meal logged" toast shows "In Health" or "Not in Health" (`food.logged.health`). A denied write keeps the meal. Undo also deletes the Health entry. No extra tap. Decision D-072.
- Core: MealHealth.swift (`FoodEntry`, `FoodRange.midpoint/metadata`, `MealHealth.log`); `HealthStore.saveFood/deleteFood` with FakeHealthStore's `savedFoods`; `LoggedMeal.inHealth`. App: `HealthKitStore.saveFood/deleteFood`, FoodView's Log and Undo.
- Tests: MealHealthTests (2), AppUITests MealHealthUITests (screenshot s018-in-health). `FEATURE_ID=S-018 scripts/gate-linux.sh` passed G1 to G5 (146 non-test lines in 5 files before the docs).
- Left undone: "In Health" shows only on the 8-second toast, since there is no meal list yet (S-019's history should read `LoggedMeal.inHealth`); a "Not in Health" meal is never retried; the denied path has a core test only (no `-uitest` launch flag makes the fake deny); the real HKCorrelation write and the custom-key delete have not run on a device; a meal with an item missing a range writes nothing for that quantity, so a meal with no known totals is "Not in Health". S-025's Day view deletes and edits logged meals only on the phone (`DayView.delete/save`), so a deleted or edited meal keeps its old Health entry; it should call `HealthStore.deleteFood` and `MealHealth.log` (out of this card's Food boundary).

## 2026-10-26 S-019 Today's food as ranges, and History with edit and delete (night agent)

- The camera has a top strip under the title: "Today", today's kcal and protein as summed low-high ranges and the meal count ("330-450 kcal", "20-27 g protein", "2 meals"); nothing logged shows "-- kcal", "-- g protein", "-- meals". No target, ring or remaining. It reloads after Log, Undo and any History change.
- History (one tap on the camera's History) is a sheet: days newest first, each with its kcal and protein totals; pending photos pinned at the top of their day; each meal with its photo thumbnail, item names, ranges, time, sources (hall or brand) and "In Health" or "Not in Health". A tap on a meal opens S-015's item editor with a Save button; Save rewrites the meal, deletes its Health entry and writes it again. Delete (one tap) removes the meal and its Health entry. Decision D-073.
- Core: FoodDay.swift (`FoodDay.on/days`, totals, `mealCount`, confidence), `MealHealth.replace/delete`. App: Food/FoodHistory.swift, FoodView's strip and History sheet, `MealEditor(action:)`, `MealCaptureStore.days/seedPhotos` and a seed at init, `-uitest-scenario food-history`.
- Tests: FoodDayTests (3 listed plus testEditReplacesHealthEntryAndDeleteRemovesIt), AppUITests MealHistoryUITests (screenshots s019-today, s019-history, s019-edited). `FEATURE_ID=S-019 scripts/gate-linux.sh` passed G1 to G5 (296 non-test lines in 8 files before the flip). S-019 flipped with check-features.py --flip.
- Naming: ids `food.strip.{kcal,protein,meals}`, `food.history.{title,done,empty}`, `food.history.day.N` with `.kcal`, `.protein`, `.pending.N.*`, `.meal.N.{items,ranges,source,photo,delete}`, `food.edit.save`.
- Left undone (diff budget): Delete has no confirm or undo; a failed Health delete or replace is not shown; History does not show a scenario's `mealHistory` meals (S-023's data-food-week), only the meal files; a meal logged from search or barcode has no photo, so its thumbnail is blank ("No photo"); the meal's capture source (photo, search, barcode) is not stored, so "source" is the items' halls or brands; History has no paging; S-025's Day view still edits and deletes meals without touching Health (it can now call `MealHealth.replace/delete`).

## 2026-10-26 S-026 Home cards show today's food, this week's workouts and the trend weight (night agent)

- With 0 taps, Home's cards now show recorded numbers instead of only "--". Data: the trend weight with "Trend weight, lb. Weigh-ins 5 of 7". Food: today's kcal range as the number with "Today, kcal. 60-80 g protein, 2 meals". Workout: sessions this week (Stezu and Health merged, as on Data) with "Sessions this week. Next: Day 1 Push". No target, remaining or score anywhere (D-032). Anything not recorded shows "--" with a nil confidence. Decision D-074.
- App: `HomeInputs` now holds `WeekWeight`, `FoodDay`, `[WeekWorkout]` and the next template's name, and `HomeInputs.load(from:)` reads them in HomeView's `.task` each time Home appears. The old target, intake, protein-floor and last-session inputs are gone, and testThreeCardsInOrder and testMissingValuesShowDashes were rewritten to the new inputs with the same checks. Each card's accessibility label is now "<label>, <subtitle>, <number>". `-uitest-scenario home-week` is data-food-week plus two meals today.
- Tests: AppTests HomeViewModelTests/testCardsShowTrackingNumbersWithoutTarget, AppUITests HomeCardsUITests (screenshots s026-home-filled, s026-home-empty). `FEATURE_ID=S-026 scripts/gate-linux.sh` passed G1 to G5 (114 non-test lines in 3 files before the docs).
- Left undone: Workout's own "Sessions this week" still counts only finished Stezu sessions by the real clock, so it can disagree with the Home card, which also counts Health workouts and seeded sessions. The next template is still the rotation's first, because Workout passes nil as the last template too. Home does not refresh while it stays open; it reads again only when it reappears.

## 2026-10-26 S-029 Logged meals copy themselves to Hermes too (night agent)

- Every Log, History save or delete, Undo and Day view save or delete now queues one `meal` record for POST /sync: id, `eaten_at`, `day` (yyyy-MM-dd on the phone's calendar), `status` (confirmed), `edited`, `in_health`, and each item with `item_id`, `name`, `source` (hall, brand or "estimate"), `halls`, `serving`, `servings`, `confidence`, `rough` and its `kcal` and `protein_g` ranges. Deletes and Undo send a tombstone (`deleted: true`, no payload). No photo is sent. Zero taps: a pass starts in the background right after the change. Decision D-075.
- Same queue and retry as S-028: a records-only `SyncBatch` in sync-state.json, resent with the same batch id until a 2xx. Settings' Hermes sync row adds the server's `records_total` ("3 samples, 1 record") and refreshes every second while open.
- Core: SyncRecord.swift (`SyncRecord`, `MealRecord`), `SyncBatch.records`, `SyncState.recordsTotal`, `HealthSync.enqueue`, a flush before GET /sync/status, `FakeVMTransport(countsRecords:)`. App: `AppEnvironment.syncMeal`, the call sites in FoodView, FoodHistory and DayView, `-uitest-scenario sync-meals` (POST /scan answers, as in photo-match).
- Tests: HealthSyncTests/testMealRecordCarriesRangesAndSource, AppUITests HermesSyncUITests/testLoggedMealIsSynced (screenshot s029-meal-synced). `FEATURE_ID=S-029 scripts/gate-linux.sh` passed G1 to G5 (173 non-test lines in 10 files before the docs).
- Left undone: workout_session, set and weigh_in records are still not sent (`SyncRecord.payload` is typed `MealRecord?`; another kind should make it an enum); meals logged before this build are never sent (no backfill from the meal files); the capture source (photo, search, barcode) is still not stored, so `source` is per item; DayView's meal edit and delete still do not touch Health (S-018/S-019 note); several quick changes queue one batch each rather than coalescing.

## 2026-10-26 S-030 Logged sets and finished workouts sync to Hermes as records (night agent)

- Log saves the logger on the phone, then queues one `set` record (id, session_id, template_key, exercise_key, exercise, pounds or null for bodyweight, reps, logged_at, kind working); Undo queues the same id as a tombstone. Finish saves the session to finished-workouts.json first, queues one `workout_session` record (id, template key and name, start, end, exercises by key and name with their sets, so swaps and custom exercises show), then writes Health and saves `inHealth`. All on S-029's queue (`AppEnvironment.syncRecords`), no extra tap. updated_at keeps milliseconds. Decision D-077.
- Backfill: the first launch/foreground with this build queues every finished session and the open logger's sets once; `SyncState.workoutsBackfilled` keeps it from running again. A sync pass asked for while one runs now makes the running pass go once more, so the last record is not left waiting.
- Core: WorkoutRecord.swift (`SetRecord`, `SessionRecord`, `WorkoutRecords.setID/backfill`, `SyncRecord.set/deletedSet/session`), `SyncRecord.setPayload/sessionPayload` with kind-based decoding, `WorkoutFinish.close/write`, `HealthSync.backfillWorkouts`. App: `AppEnvironment.syncRecords/syncWorkout/workoutNames/backfillWorkouts`, Log and Undo in WorkoutLoggerView, `WorkoutView.keep`.
- Tests: WorkoutRecordTests (3), AppUITests HermesSyncUITests/testLoggedSetsAndFinishedWorkoutAreSynced (screenshot s030-workout-synced). `FEATURE_ID=S-030 scripts/gate-linux.sh` passed G1 to G5 (291 non-test lines in 7 files before the docs).
- Left undone: the backfill and the Finish record have no AppTests of their own (core tests cover them); a failed Health write is still not retried; a session deleted in the Day view sends no tombstone; set records carry no rest or RPE; exercise keys for names that are in neither the library nor a template are sent as null.
