# Decisions

Each decision gets one entry. Each entry records what was decided, who decided it, why, the alternatives that were rejected, and what would reverse it. Status is one of: decided, proposed, open.

The research notes cited here are kept private, because they contain personal health details. Everything an agent needs to build is in SPEC.md, DESIGN.md and AGENTS.md.

## D-001 Native iPhone app (SwiftUI), not a web app

- Status: decided by Isaac, 2026-10-24.
- Why: the Princeton Eats web app logged 0 meals. Isaac's reason: "too ugly and clunky... too many clicks". A native app also reads HealthKit directly, and it can use the camera and LiDAR.
- Rejected: a web app on the VM plus Health Auto Export. It is the easiest setup for agents to build and test, but this is the second time a web version went unused. React Native (Expo) is the other rejected option, because it adds a layer without fixing the HealthKit or camera access.
- Cost: agents on the Linux VM cannot compile or run SwiftUI. See private research note 02 for how the build loop reaches a Mac.
- Reverse if: the Mac can't be added to the overnight loop and a once-a-morning build turns out to be too slow to make progress.

## D-002 Food logging is photo or scan only

- Status: decided by Isaac, 2026-10-24.
- Why: manual entry is what made the last app a hassle.
- Open: how accurate photo estimation really is, and whether a single confirm tap is still needed. See private research note 03.

## D-003 Show the numbers

- Status: decided by Isaac, 2026-10-24.
- What: this drops the August Hive rule "collect, never analyze". Isaac will adjust his routine, sleep, food and gym from the data.
- Design: the home screen is the mock with numbers (the Data, Food and Workout cards).

## D-004 This is Stezu's main manual-input app

- Status: decided by Isaac, 2026-10-24.
- Why: nearly all of the data he has to enter by hand is health data.

## D-005 The health app is the test case for the engineering loop

- Status: decided by Isaac, 2026-10-25.
- What: the app itself is not the focus. The focus is the engineering loop, meaning overnight building that can run several projects in parallel. This app is the first project it runs on.
- Consequence: judge each step by what it teaches about the loop (gates, review cost, failure modes), as well as by the app features it ships.

## D-006 Builder: Hermes, with subagents for all research and build work

- Status: decided by Isaac, 2026-10-24.
- Open: which overnight setup to use (private research note 02), and how he will understand and defend the work built overnight (private research note 04).

## D-007 Public GitHub repo; GitHub-hosted macOS runners for CI; no Xcode Cloud

- Status: decided by Isaac, 2026-10-25 ("build in public").
- Why: GitHub-hosted runners, macOS included, are free for public repos. Xcode Cloud only mattered as a way to keep a private repo's macOS minutes free.
- Constraint: the repo never contains health data, API keys or personal identifiers. The photo-analysis call goes through the VM with a per-device token, so no model key ships in the app.

## D-008 Free Apple developer account for now

- Status: decided by Isaac, 2026-10-25.
- Cost: the app expires every 7 days, and he reinstalls it from the Mac. TestFlight is not available. Whether HealthKit background delivery works on a free account is untested.
- Reverse if: the weekly reinstall gets in the way, or background delivery proves necessary.

## D-009 Wearable data: Helio Strap through Zepp into Apple Health

- Status: decided by Isaac, 2026-10-25.
- Open: which HealthKit types Zepp actually writes. The Hive note says raw heart rate, HRV, sleep stages, SpO2, steps and workouts, but not Zepp's readiness or BioCharge scores. That has not been checked on his phone. The app should list what is present on first launch.

## D-010 Weight: one-tap weigh-in at the gym

- Status: decided by Isaac, 2026-10-25. Food stays photo or scan only; gym sets are logged with taps.
- Update 2026-10-25: he has no scale, so he weighs in on gym days, about 5 a week on the 5-day split. That clears L1's floor of 4 a week. Days without a weigh-in are missing data, not zero.
- Cost: gym weigh-ins are noisier than morning ones. Food, water and sweat all vary by time and session. The trend smoothing absorbs random noise. A habit that changes between before and after the workout adds a bias, so he always weighs at the same point.
- Reverse if: the trend is too noisy to set a target after 3 weeks. Then a cheap home scale for morning weigh-ins is the fix.

## D-011 Defend before decide (the learning loop)

- Status: proposed, 2026-10-25. Comes from private research note 04, where it was drafted as "D-007" before that number was used.
- What: the night agent writes at most 3 mechanism decisions per night in the problem-first format. The questions go in the morning brief (no separate file). A Mermaid diagram starts once the core has more than 3 modules. A decision counts as decided only after a closed-book defense or an explicit overturn. Six or more undefended decisions trigger a consolidation night.
- Rejected:
  - DeepWiki or tutorial generators: exposure without generation.
  - A DeepTutor mastery path in week 1: recognition items, a confidence-capture gap, an untested PUT.
  - rederive as the nightly tool: it reconstructs decisions after the fact and has no Swift import graph or spacing.
- Reverse if: the 2-week exit test shows he can't reconstruct defended decisions cold, or sessions happen on fewer than 4 of 7 mornings even at the 5-minute floor.

## D-012 Ecosystem rule: loops before infrastructure

- Status: proposed, 2026-10-25. Comes from private research note 06. Full design: vault `07-Projects/Active/Ecosystem/Ecosystem Design.md`.
- What: every part of the system is a loop with a decision, observation, rule, cadence, end condition and loop-health numbers. Connections are graded links taken from evidence; the table in the design note becomes a file only when a second loop needs it. A new loop or project is added only after the current ones meet their floors (4 weigh-ins a week; 4 morning sessions in 7 days).
- Rejected:
  - Karina's model-everything design: 37 variables, a causal engine and a blackboard of specialist agents. It built infrastructure before any loop closed.
  - Mining all-pairs correlations: false positives.
- Reverse if: two loops run stably for 6 weeks and the hand-written graph becomes the bottleneck.

## D-013 The Hermes kanban worker writes the code; no Claude Code inside cards

- Status: proposed, 2026-10-25. Raised by private research note 07 (B2).
- Problem: something has to edit the code inside an unattended card, with a cap on time and usage, and the completion judge has to see the real work.
- Options:
  - (a) The Hermes worker edits directly in goal mode: 15 turns, 2 hours per run.
  - (b) A one-shot card that runs `claude -p` with `--max-budget-usd`.
  - (c) Both nested: goal mode plus `claude -p`.
- Choice: (a). It is the simplest and uses one loop and one process. Option (c) gives three loops, two memory footprints, and a judge that only sees summaries.
- Reverse if: the dry run shows the Hermes worker can't finish F-001-sized cards in 15 turns while Claude Code can.

## D-014 Weekly numbers by default; daily only for today's intake

- Status: proposed, 2026-10-25. Changes D-003's mock (rejected option: daily numbers on every card). Raised by private research note 06 and private research note 07 (S8).
- Problem: show numbers he can act on without a daily verdict that drives anxiety or chasing noise.
- Choice: today's intake against the target, because it is actionable. Trend weight, weekly protein average and lifts are shown weekly. HRV and sleep are context only. No composite score.
- Reverse if: after 4 weeks he finds he wants a daily number and it hasn't changed his behavior for the worse.

## D-015 Tests are XCTest methods named test...

- Status: proposed, 2026-10-25 (scaffold card).
- Problem: the gates must notice when a card weakens or deletes tests, using text checks that run on Linux before any Mac sees the code.
- Given: Swift 6.4 on Linux runs both XCTest and Swift Testing. features.json names tests as Target.Class/testMethod. G3 counts `func test` per test file.
- Constraints:
  - Text-only checks on Linux: a framework whose tests are not recognizable by name breaks the G3 count.
  - One naming scheme for core and app: two schemes break the existence check in check-features.py.
  - Both runners filter by name: names must work with `swift test --filter` and `xcodebuild -only-testing`.
- Options:
  - (a) XCTest only, every test method named test....
  - (b) Swift Testing only, counted by the `@Test` attribute.
  - (c) Both frameworks, with two counting rules.
- Decision: (a). It is the only option where one text pattern covers both targets and both runners.
- Evidence: scripts/diff-budget.sh, scripts/check-features.py, Packages/StezuCore/Tests, App/Tests; the scaffold commit on main.
- Reverse if: a rule needs Swift Testing's parameterized cases (for example a table of L1 cases) badly enough to move the count to `@Test`.

## D-016 Gates G2 and G3 judge branches, not main

- Status: proposed, 2026-10-25 (scaffold card).
- Problem: the feature-ledger and diff-budget checks need a baseline, and a push to main has no separate baseline to compare against.
- Given: cards run on wt/F-xxx branches and merge through pull requests. Branch protection requires only linux-core, with strict off and admins not enforced.
- Constraints:
  - Comparing every main push with its parent breaks the scaffold and any multi-card merge, which exceed the budget by design.
  - Admins can push to main directly, so a card pushed straight to main skips the one-feature rule and the budget.
- Options:
  - (a) On main, reduce G2 to a schema check and skip G3.
  - (b) Compare each main push with its first parent.
  - (c) Enforce protection for admins, so every change goes through a pull request.
- Decision: (a) for week 1, because Isaac still pushes small fixes directly. Night agents always work on wt/F-xxx branches.
- Evidence: scripts/gate-linux.sh, scripts/check-features.py, scripts/diff-budget.sh, .github/workflows/ci.yml; the scaffold commit on main.
- Reverse if: any night card lands on main without a pull request. Then switch to (c).
