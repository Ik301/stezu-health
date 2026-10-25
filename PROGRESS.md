# Progress

Newest entry first. One entry per card: the date, the card, what changed, the gate result and what comes next.

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
