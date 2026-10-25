# Progress

Newest entry first. One entry per card: the date, the card, what changed, the gate result and what comes next.

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
