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

## D-017 Trend confidence from weigh-in count and age

- Status: proposed by night agent, 2026-10-25 (F-001).
- Problem: a trend value alone does not say how much it can be trusted. A trend built from one reading, or one last updated a week ago, looks the same as one built from two weeks of steady gym weigh-ins.
- Given: SPEC.md requires every derived value to carry a level and a reason. Weigh-ins come about 5 a week. With alpha 0.1 per day, a reading's weight halves in about 6.6 days, so the last 14 days carry about 77% of the trend.
- Constraints:
  - Must be explainable in one line on screen: an opaque statistic (a variance or an effective sample size) breaks the "reason" the UI shows.
  - Must drop when data stops: a count over all history keeps saying "high" after weeks without a weigh-in.
  - Must be configurable: hard-coded bars break the no-personal-numbers rule once L1 needs its own floor.
- Options:
  - (a) Count weigh-in days in a 14-day window ending on the day read, plus days since the last one. High: 8 or more and at most 3 days old. Medium: 4 or more and at most 7 days old. Otherwise low.
  - (b) Sum the EWMA weights (effective number of readings) and map it to levels.
  - (c) Total weigh-ins since the first one.
- Decision: (a). It matches L1's floor of 4 a week, reads as a plain sentence ("10 weigh-ins in the last 14 days; last one 0 days ago"), and decays with staleness. All five numbers live in TrendWeightConfig.
- Evidence: Packages/StezuCore/Sources/StezuCore/TrendWeight.swift (`confidenceFor`), Confidence.swift, TrendWeightTests/testTrendCarriesConfidence; the F-001 commit on wt/F-001.
- Reverse if: the levels disagree with how the trend actually behaves after 3 weeks of real use, or F-003 needs a weekly rather than rolling count.

## D-018 Weigh-ins are bucketed into calendar days before smoothing

- Status: proposed by night agent, 2026-10-25 (F-001).
- Problem: the gap d in 1 - (1 - alpha)^d has to be a whole number of days, but weigh-ins are timestamps. Two readings can fall on the same day, a reading near midnight can land on either side, and clock changes make some days 23 or 25 hours long.
- Given: weigh-ins are at the gym, at most once a day in practice. HealthKit samples are absolute timestamps.
- Constraints:
  - Elapsed seconds / 86,400 breaks on daylight-saving days (fractional or off-by-one gaps).
  - Treating same-day readings as separate points breaks the formula: d = 0 gives the second reading weight 0, so it is silently thrown away.
  - A fixed UTC day breaks the user's notion of "today" for an evening weigh-in in US time zones.
- Options:
  - (a) Start of day in a configurable Calendar (default Calendar.current); gap = calendar day difference; same-day readings averaged into one reading.
  - (b) Fractional days from elapsed time, alpha applied continuously.
  - (c) Same-day duplicates: keep the last reading instead of the mean.
- Decision: (a). Day differences come from `Calendar.dateComponents(.day)` between day starts, which handles DST. Mean over keep-last because neither reading is known to be wrong. Readings that are 0, negative or not finite are dropped as not-a-reading.
- Evidence: Packages/StezuCore/Sources/StezuCore/TrendWeight.swift (`dailyReadings`, `dayIndex`), TrendWeightTests/testMissingDaysAreNotZero; the F-001 commit on wt/F-001.
- Reverse if: weigh-ins start happening before and after a workout on the same day; then the mean mixes two biases and keep-first is better (see D-010).

## D-019 What the trend API returns with no data, and between weigh-ins

- Status: proposed by night agent, 2026-10-25 (F-001).
- Problem: callers ask for the trend on arbitrary days: before any weigh-in, with an empty history, and on days between weigh-ins. Each case needs an answer that cannot be mistaken for a weight.
- Given: "absent is not zero" (AGENTS.md rule 5). The Data screen shows "--" for missing values. F-002 and F-003 read the trend at window edges that may not be weigh-in days.
- Constraints:
  - Returning 0 breaks every downstream mean and difference.
  - Interpolating or filling missing days breaks step 3 of F-001 (missing days do not update the trend).
  - Throwing an error breaks simple call sites for a normal, expected state.
- Options:
  - (a) `series` returns one point per weigh-in day (empty array for no data). `estimate(asOf:)` returns nil when no weigh-in exists on or before that day; otherwise the last trend value held flat, with days-since-last and a confidence that drops as it ages.
  - (b) A dense daily series with a nil trend on days without a weigh-in.
  - (c) An enum result with an explicit `.insufficientData(reason)` case.
- Decision: (a). Nil maps straight to "--", and holding the last value is exactly what an EWMA does when nothing new arrives. The stale-data signal lives in the confidence, not in the number.
- Evidence: Packages/StezuCore/Sources/StezuCore/TrendWeight.swift (`series`, `estimate`), TrendWeightTests/testMissingDaysAreNotZero, testFirstWeighInSeedsTrend; the F-001 commit on wt/F-001.
- Reverse if: F-002 or F-003 need to tell "no data yet" apart from "data too stale" with a reason string; then move to (c).

## D-020 How a dining menu reaches core without a network stack

- Status: proposed by night agent, 2026-10-25 (F-010).
- Problem: core has to fetch and decode dining menus from the VM endpoint, but it must build and test on Linux with no networking import, and the endpoint URL and token are not approved yet.
- Given: AGENTS.md keeps StezuCore free of platform imports. F-010 step 4 leaves the URL and token handling to Isaac. Tests may not touch the network.
- Constraints:
  - Calling URLSession from core breaks the Linux build boundary and puts the URL and token in core.
  - A transport that takes a full URL request breaks the approval line, because core would then shape the URL and headers.
  - A synchronous transport breaks the app's real implementation, which is async.
- Options:
  - (a) An async `DiningMenuTransport` protocol that receives an abstract `DiningMenuRequest` (hall, date) and returns a status code and body. The app's transport owns URL, path, token and headers. `DiningMenuClient` maps status and decodes.
  - (b) The transport returns an already decoded `DiningMenu`, and core holds only models.
  - (c) Core builds a `URLRequest` and the transport only executes it.
- Decision: (a). Status mapping and decoding stay in core where they are tested; everything that needs approval stays in the app.
- Evidence: Packages/StezuCore/Sources/StezuCore/DiningMenu.swift (`DiningMenuTransport`, `DiningMenuClient.menu`), DiningMenuTests/testClientUsesInjectedTransport; commit 3455c84 on wt/F-010.
- Reverse if: the endpoint shape is approved and fixed; then core could own the path and query (c) so the app transport shrinks to a token and a base URL.

## D-021 An unavailable menu is a separate state, never an empty menu

- Status: proposed by night agent, 2026-10-25 (F-010).
- Problem: a hall may be closed, FoodPro may not have published a day yet, or the scrape may return a menu with no dishes. Callers must not show any of these as "nothing to eat".
- Given: "absent is not zero" (AGENTS.md rule 5). The endpoint JSON is not fixed yet; this card defines it as an envelope `{"status": "available", "menu": {...}}` or `{"status": "unavailable", "reason": "..."}`.
- Constraints:
  - Returning `DiningMenu` with empty meals breaks rule 5: an empty list reads as a real, empty menu.
  - Returning a bare nil drops the reason, which the Food screen needs to say why "--" is shown.
  - Throwing for a closed hall breaks call sites for a normal, expected state.
- Options:
  - (a) `DiningMenuResult` enum, `.available(DiningMenu)` or `.unavailable(reason:)`. HTTP 404, `"status": "unavailable"` and an available menu with no items all map to `.unavailable`. Other statuses and malformed JSON throw.
  - (b) `DiningMenu?` with nil for every absent case.
  - (c) Keep empty menus as `.available` and let the UI decide.
- Decision: (a). Missing nutrition fields on a dish decode to nil, not 0, for the same reason.
- Evidence: Packages/StezuCore/Sources/StezuCore/DiningMenu.swift (`DiningMenuResult`, `DiningMenuClient.decode`), DiningMenuTests/testUnavailableMenuIsAbsentNotEmpty; commit 3455c84 on wt/F-010.
- Reverse if: the endpoint starts sending meals that are legitimately empty while others are open; then empty meals should be dropped per meal, not per menu.

## D-022 A protein window with any unlogged day returns insufficient data

- Status: proposed by night agent, 2026-10-25 (F-004).
- Problem: the 3-day mean of daily protein needs a value for each day, but food logging is optional. A day with no logged meal has to be handled without inventing an intake.
- Given: SPEC.md says fewer than 3 days of logged food gives "insufficient data", not a flag. AGENTS.md rule 5: absent is not zero. Meal estimates arrive as low/high ranges in grams.
- Constraints:
  - Counting an unlogged day as 0 g breaks rule 5 and raises a false flag after any skipped day.
  - Averaging over only the logged days in the window breaks the "fewer than 3 days" rule (2 days would still yield a mean).
  - Reaching back past the window for older days breaks "rolling 3-day": a flag could rest on last week's food.
- Options:
  - (a) Fixed window of the read day and the 2 calendar days before it; every day must have at least one valid meal, otherwise `.insufficientData` with days logged and days required.
  - (b) The last 3 logged days, however far back.
  - (c) Logged days in the window only, with lower confidence when fewer than 3.
- Decision: (a). Days are calendar-day buckets in a configurable Calendar (as D-018). A meal with a negative or non-finite end is dropped and does not make its day logged; a 0 g estimate is a real value. A reversed range is reordered, and the flag reads only the low end; the high-end mean is returned as context.
- Evidence: Packages/StezuCore/Sources/StezuCore/ProteinFloor.swift (`check`, `validRange`), ProteinFloorTests/testFewerThanThreeDaysIsInsufficient; the F-004 commit on wt/F-004.
- Reverse if: real use shows whole-day gaps are common enough that the flag is almost never evaluated; then consider (b) with a staleness limit.

## D-023 Protein check confidence from the fewest meals on one day

- Status: proposed by night agent, 2026-10-25 (F-004).
- Problem: a day can count as logged with only a snack on it, which makes its total look low. The check needs to say how much its mean can be trusted.
- Given: every derived value carries a level and a reason (SPEC.md). The floor uses low ends, so it already errs toward flagging.
- Constraints:
  - A level from the estimate width breaks once ranges come from one model with a fixed spread; it would say nothing about missed meals.
  - A level without a reason breaks the Food screen's one-line explanation.
- Options:
  - (a) High when every day in the window has at least `highMinMealsPerDay` meals (default 2), otherwise low; the reason names the fewest meals on one day.
  - (b) Always medium, since all inputs are estimates.
- Decision: (a). A one-meal day is the likeliest sign of incomplete logging, and a low-confidence flag tells the UI to soften it.
- Evidence: Packages/StezuCore/Sources/StezuCore/ProteinFloor.swift (`check`); the F-004 commit on wt/F-004.
- Reverse if: meal counts vary so much by habit (one large meal a day) that most checks read low.

## D-024 Partial-day detection uses 7-day blocks from the window start

- Status: proposed by night agent, 2026-10-25 (F-002).
- Problem: SPEC.md says a day is partial when its intake is under 50% of "that week's" median, but does not say where a week starts, and a window of 21 days does not line up with calendar weeks.
- Given: the window is 21 days ending on the day read. Days with no log at all are absent. Intake comes as individual entries with timestamps.
- Constraints:
  - Calendar weeks (locale first weekday) break reproducibility: the same data gives different results with a different locale, and the first and last weeks of the window are cut short.
  - A rolling 7-day median around each day breaks the one-line explanation and needs data outside the window at the edges.
  - Counting absent days as 0 in the median breaks rule 5 and pushes real low days into "partial".
- Options:
  - (a) Three fixed 7-day blocks counted from the window start; median over the block's logged days only.
  - (b) Calendar weeks from `Calendar.firstWeekday`.
  - (c) A centred rolling 7-day median per day.
- Decision: (a). Entries are summed per calendar day (the trend config's calendar), entries of 0, negative or not-finite kcal are dropped as not-intake, and each logged day is compared with 50% of its block's median. Partial days are excluded from the mean and counted in the result.
- Evidence: Packages/StezuCore/Sources/StezuCore/Expenditure.swift (`estimate`, `median`), ExpenditureTests/testPartialDaysAreExcluded; the F-002 commit on wt/F-002.
- Reverse if: the window length stops being a multiple of 7, or partial days cluster at block edges in real use.

## D-025 Expenditure returns an explicit insufficient-data result, and its confidence is the weakest input

- Status: proposed by night agent, 2026-10-25 (F-002).
- Problem: the estimate depends on two inputs that fail independently (intake logging and the trend at both window edges), and the caller has to show "--" with a reason, never a number, when either is missing.
- Given: D-019 left the trend API as an optional and said to move to an enum when a caller needs a reason string. `TrendWeight.estimate(asOf:)` returns nil before the first weigh-in and carries its own confidence.
- Constraints:
  - Returning nil alone breaks the reason the Data screen should show ("9 full intake days; needs 14").
  - Returning 0 kcal breaks rule 5 and F-003, which would read it as a real expenditure.
  - A confidence from intake alone breaks when the trend at the window start is a week stale.
- Options:
  - (a) `ExpenditureResult` enum: `.estimate(ExpenditureEstimate)` or `.insufficientData(reason:)`, with an `estimate` accessor that is nil for the second case. Confidence = min(intake level, start trend level, end trend level).
  - (b) An optional estimate plus a separate status call.
  - (c) Always return an estimate, with low confidence when data is thin.
- Decision: (a). Insufficient when fewer than 14 full intake days are in the window, or no weigh-in exists on or before the day before the window starts. Trend change = trend at the end day minus trend on the day before the window, so it spans exactly 21 days. Intake is high with 18 or more full days, otherwise medium; the trend can pull it lower. All thresholds live in ExpenditureConfig.
- Evidence: Packages/StezuCore/Sources/StezuCore/Expenditure.swift (`ExpenditureResult`, `estimate`), ExpenditureTests/testInsufficientDataIsNotZero, testExpenditureFromIntakeAndTrendChange; the F-002 commit on wt/F-002.
- Reverse if: F-003 needs to act on a low-confidence estimate differently from insufficient data, or 14 days proves too strict for real logging habits.

## D-026 Where the last session's numbers come from

- Status: proposed by night agent, 2026-10-25 (F-008).
- Problem: the Workout screen shows, for the current exercise, what was lifted last time. Exercises are not done every session, and the session in progress already contains sets of the same exercise.
- Given: sessions are values (`WorkoutSession`) held by the app; there is no store yet. F-009 builds its suggestion on the same numbers.
- Constraints:
  - Taking the previous session as a whole breaks on skipped exercises (bench not done last time shows nothing, though it was done the time before).
  - Including the session in progress breaks the comparison: the second set would show the first set as "last time".
  - A cached per-exercise "last numbers" field breaks when a session is edited or deleted (it goes stale silently).
- Options:
  - (a) Derive on read: the latest session that started strictly before a given date and has at least one set of that exercise; nil when none.
  - (b) Only the immediately previous session; nil if the exercise was skipped there.
  - (c) Keep a per-exercise cache updated on each logSet.
- Decision: (a). `WorkoutHistory.lastSession(of:before:in:)` is a pure function over the session list, so it cannot go stale and needs no storage. Exercise identity is the exact name string. The result carries a confidence that drops from high (14 days or less) to medium (42) to low as the session ages, with the set count and age as the reason.
- Evidence: Packages/StezuCore/Sources/StezuCore/WorkoutSession.swift (`WorkoutHistory`), WorkoutSessionTests/testLastSessionNumbersPerExercise; the F-008 commit on wt/F-008.
- Reverse if: exercise names get renamed or aliased in the app; then identity moves to a stable exercise ID.

## D-027 The rest timer stores a start time and reads an injected clock

- Status: proposed by night agent, 2026-10-25 (F-008).
- Problem: the rest timer has to show the right time left after the phone is locked or the app is suspended mid-rest, and it has to be testable without waiting real seconds.
- Given: iOS suspends apps and stops their timers in the background. SwiftUI views can redraw on a `TimelineView` tick.
- Constraints:
  - A counter decremented by a repeating Timer breaks on suspension (it stops counting) and needs real time in tests.
  - Reading `Date()` inside StezuCore breaks testability.
  - A Swift `Clock`/`Instant` generic breaks simple use with Foundation `Date`s that the rest of the core uses.
- Options:
  - (a) Store `startedAt`; compute remaining from a `now: () -> Date` closure passed at init. The view only redraws; the core owns no timer.
  - (b) Store `startedAt` and pass `now` into every read.
  - (c) A Combine/async ticking timer in the core.
- Decision: (a). State is idle, resting(remaining) or done(overBy); remaining is nil when idle and never negative. Starting again restarts from the clock. The app passes `{ Date() }`; tests pass a closure over a local variable.
- Evidence: Packages/StezuCore/Sources/StezuCore/RestTimer.swift, RestTimerTests/testRestTimerUsesInjectedClock; the F-008 commit on wt/F-008.
- Reverse if: the timer must fire a notification when rest ends while the app is backgrounded; that needs a scheduled local notification in the app, fed from `startedAt + duration`.

## D-028 The weekly target rule is stateless; the caller passes the last change date

- Status: proposed by night agent, 2026-10-25 (F-003).
- Problem: SPEC.md allows at most one target change per week, so the rule has to know when the target last moved, and something has to remember that across app launches.
- Given: StezuCore has no storage and no platform imports. The trend, expenditure and protein rules are pure functions of their inputs.
- Constraints:
  - Storing the change history inside StezuCore breaks the no-platform, pure-package rule and makes tests depend on state.
  - Inferring the last change from the target history breaks when Isaac edits the target by hand.
  - Calendar weeks (locale first weekday) break reproducibility, as in D-024.
- Options:
  - (a) `WeeklyTarget.evaluate(asOf:currentTarget:weighIns:lastChange:config:)` takes the last change day (nil if never); the app stores it and the new target.
  - (b) A stateful `WeeklyTargetEngine` object that keeps its own history.
  - (c) Run the rule only on a fixed weekday.
- Decision: (a). A due raise or lower is held, with action `.alreadyChangedThisWeek`, when the last change was fewer than 7 calendar days before the read day (`minDaysBetweenChanges`). The result always carries the previous and new target, so the app writes back `newTarget` and, on raise or lower, today as the last change.
- Evidence: Packages/StezuCore/Sources/StezuCore/WeeklyTarget.swift (`evaluate`), WeeklyTargetTests/testAtMostOneChangePerWeek; the F-003 commit on wt/F-003.
- Reverse if: the app needs a history of decisions for the Data screen, in which case the stored log can supply `lastChange`.

## D-029 Data sufficiency and trend rate are counted in calendar days back from the read day

- Status: proposed by night agent, 2026-10-25 (F-003).
- Problem: SPEC.md asks for 4 weigh-ins "in the current week", 21 days of data and a trend rate over "the last 3 weeks", without fixing where those spans start.
- Given: `TrendWeight.estimate(asOf:)` returns nil before the first weigh-in and carries its own confidence. Every decision needs a reason and a confidence.
- Constraints:
  - Counting the week from a locale first weekday breaks early in the week, when 4 weigh-ins are impossible.
  - A 21-day span that does not reach the day the rate window starts breaks the rate, because the start trend would be nil.
  - Returning a rate of 0 when data is thin breaks rule 5 and would trigger a raise.
- Options:
  - (a) Rolling spans: weigh-in days in the 7 days ending on the read day; days of data = days from the first weigh-in to the read day; rate = (trend today - trend 21 days ago) / 3.
  - (b) Calendar weeks and a rate from a linear fit over the weigh-ins.
- Decision: (a). Days of data is checked first, then the week count; either failure returns `.insufficientData` with the target unchanged, a nil `trendRate`, low confidence and the counts in the reason. "More than" is strict, so a gap exactly on 0.15 or 0.25 holds. Confidence of a computed decision is the weaker of the two trend confidences. All thresholds, both bands (0.25 to 0.5 lb/week, 100 to 150 kcal) and the steps live in `WeeklyTargetConfig`; a rate or step outside its band traps with `precondition`, like the trend alpha (D-017).
- Evidence: Packages/StezuCore/Sources/StezuCore/WeeklyTarget.swift (`WeeklyTargetConfig`, `evaluate`), WeeklyTargetTests (all five tests); the F-003 commit on wt/F-003.
- Reverse if: the EWMA lag makes the 3-week trend rate too slow to react, or Isaac wants the decision on a fixed weekday.

## D-030 Which sets the double-progression rule reads

- Status: proposed by night agent, 2026-10-25 (F-009).
- Problem: the suggestion for next time is derived from last session's sets, but a session can mix warm-up sets at lighter weights with working sets, and some exercises carry no load.
- Given: `WorkoutHistory.lastSession` (D-026) returns every set of the exercise in log order, with `pounds == nil` for bodyweight and a confidence that fades with age.
- Constraints:
  - Reading every set breaks the rule: a warm-up set of 10 reps at a light weight would count toward "all sets at the top".
  - Reading only the last set breaks on a dropped final set and ignores the rest.
  - Treating bodyweight as 0 lb breaks "absent is not zero" and would show "0 lb" on screen.
- Options:
  - (a) Working sets = the sets at the heaviest weight of the session; bodyweight-only sessions use all sets.
  - (b) Every set counts.
  - (c) The app tags sets as warm-up or working.
- Decision: (a). `DoubleProgression.suggest(after:config:)` takes the last session's numbers and returns nil with no last session. If every working set reached the top of the range it adds one weight step and resets each set to the bottom of the range; otherwise each working set below the top gets one more rep. Bodyweight below the top keeps `pounds == nil`; bodyweight at the top gets a first added load of one step. The suggestion inherits the last session's confidence level, and the reason names how many working sets are under the top.
- Evidence: Packages/StezuCore/Sources/StezuCore/DoubleProgression.swift, DoubleProgressionTests; the F-009 commit on wt/F-009.
- Reverse if: the app starts tagging warm-up sets (option c), or Isaac's programs use back-off sets at a lighter weight that should progress too.

## D-031 Home cards are computed from optional core results and an injected clock

- Status: proposed by night agent, 2026-10-25 (F-005).
- Problem: the home screen must show three cards whose values come from four core rules that may not have run yet, and one card must turn black depending on the time of day.
- Given: the core rules return optional or insufficient-data results with a confidence (D-017 to D-029). There is no app storage or HealthKit import yet. AppTests run only on the macOS simulator.
- Constraints:
  - Calling the core rules from the view model breaks the thin-app rule and makes the view model own data loading it does not have.
  - Reading `Date()` inside the view breaks testing of the inverted card.
  - Formatting a missing value through a number formatter breaks rule 5, because nil would become 0.
- Options:
  - (a) A value-type `HomeViewModel` maps a `HomeInputs` struct of optional core results to `[HomeCard]`, and reads an injected `now` closure plus a configurable start-hour schedule for the inverted card.
  - (b) An observable view model that loads the data itself and runs a timer.
- Decision: (a). Each nil input gives "--" and a nil confidence; Food shows each half of "intake / target" separately, so a known intake with no target reads "600 / --". The schedule defaults to 5 Data, 11 Food, 16 Workout, 20 Food (hours before the first start wrap to the last entry); these are defaults, not personal numbers. HomeView re-reads the clock in a `TimelineView(.everyMinute)`.
- Evidence: App/Sources/HomeViewModel.swift, App/Sources/HomeView.swift, App/Tests/HomeViewModelTests.swift; the F-005 commit on wt/F-005.
- Reverse if: the app gains a store that publishes changes, at which point the inputs come from it, or the default hours do not match when Isaac actually weighs in, eats and trains.

## D-032 v1 is tracking only

- Status: decided by Isaac, 2026-10-25.
- What: v1 of the app records and shows data. Workout logging (sets, weights, reps, templates and prebuilt workouts), food logging by photo, and a Data area showing what was recorded plus Apple Health data. No targets, suggestions, adjustments or readiness scores in the UI.
- Why: the app has to be usable before anything adjusts behavior. The first phone test showed three blank cards and no way to log.
- Consequence: the core rules already built stay in the repo but are not surfaced in v1: WeeklyTarget (F-003), Expenditure (F-002), ProteinFloor (F-004) and DoubleProgression (F-009). L1's weekly adjustment (D-012) waits; its 3-week data window fills in the meantime.
- Reverse if: the app is in daily use and the adjustment loop is designed on top of it.

## D-033 v1 scope decisions from the 2026-10-25 walkthrough

- Status: decided by Isaac, 2026-10-25.
- Build all three areas (Workout, Food, Data) at once.
- Apple Health read and write approved: HealthKit entitlement, body mass read and write, workouts, dietary energy and protein writes, and the reads in the Data area.
- Rest timer on the lock screen as a Live Activity in v1. It is untested whether a free account can build the widget extension; check on the device.
- Food opens straight into the camera.
- "This week" means Monday to Sunday.

## D-034 The public repo never holds personal data, including seeds

- Status: decided by Isaac, 2026-10-25 ("generic seed for public repo, always, all data").
- What: no personal data of any kind is committed, ever. That covers his training program, body stats, intake, health samples, hall preferences, IPs, tokens and server addresses. Prebuilt workouts in the repo are generic. His own program is imported on the device from a private file and never committed.
- Why: the repo is public (D-007).

## D-035 Food: identify across all dining halls; editable item list; text search and barcode in v1

- Status: decided by Isaac, 2026-10-25. Amends D-002 (photo or scan only).
- What:
  - A photo is matched against the menus of every dining hall open for that meal, not one chosen hall. The matched hall shows per item.
  - After a photo, the identified items appear as an editable list: replace an item (through search), remove it, change servings in half steps, or add an item.
  - A search bar on the camera screen finds dining-hall items, restaurant dishes and packaged foods by text, with a rough text estimate as the fallback.
  - Barcode scanning is in v1.
  - The recent-meal shortcuts are removed.
- Why: he doesn't always eat at the same hall, and a wrong guess needs a simple fix he controls.

## D-036 The food server: where model access and device tokens live

- Status: proposed by the server agent, 2026-10-25.
- Problem: the phone needs menus, photo identification, search and barcode lookups from somewhere that can call a model, but the phone must not hold a model key, the service must not be reachable from the internet, and nothing about its address or credentials may reach the public repo.
- Given: report 09 section 7 (the phone talks only to the VM over Tailscale with a per-device bearer token); D-034 (no tokens, IPs or server URLs in the repo); a local Claude proxy already runs on the VM; the VM has about 4 GB of free memory.
- Constraints:
  - Tokens, keys or the bind address in the repo break D-034.
  - Binding to all interfaces makes the tailnet-only rule depend on the firewall alone.
  - Hard-wiring the local proxy breaks the later move to a paid API key.
  - A heavier stack (a database server, task workers) breaks the memory budget and adds operations work.
- Options:
  - (a) One FastAPI process with a SQLite cache, run as a systemd user service bound to the tailnet address. Tokens, bind address, model base URL, key file and model id live in an env file outside the repo (~/.config/stezu/server.env, mode 0600). The key is read from its file at call time and never copied.
  - (b) The same with the stdlib HTTP server: no dependencies, but hand-written routing, multipart parsing and validation.
  - (c) Call the model from the phone with a key in the keychain.
- Decision: (a). The env file on the VM points at the local proxy with claude-sonnet-4-6 at temperature 0; the code defaults to the public API so a paid key replaces the proxy by editing two lines. The server work lands as a short series of PRs so each stays inside the G3 diff budget; tests live in server/Tests so the budget's test rule applies.
- Evidence: server/stezu_server/config.py, server/stezu_server/app.py, server/README.md, server/Tests/test_core.py.
- Reverse if: the phone must reach the server off the tailnet (then Tailscale Funnel or a public HTTPS endpoint with the same tokens), or the proxy goes away (set STEZU_ANTHROPIC_API_KEY and the base URL).

## D-037 A photo estimate is a range built from the menu values and the model's confidence

- Status: proposed by the server agent, 2026-10-25.
- Problem: for each food on the plate the model returns one servings number and a confidence. A single calorie number would hide how unsure the estimate is, and D-035 asks for ranges.
- Given: report 03 section 6 expects about 15-25% per-meal error on campus with a good depth scan, 20-35% when depth is poor, and 35-50% (biased low) open-world. FoodPro gives kcal and protein per listed serving. The same recipe is often served at several halls.
- Constraints:
  - Letting the model invent ranges for menu items throws away the FoodPro numbers and gives different widths for the same item and portion.
  - One fixed width ignores both depth quality and identification confidence.
  - A narrow open-world range overstates accuracy, and the expenditure estimator needs to know which meals are rough.
  - Listing the same dish once per hall splits the model's choice between identical candidates.
- Options:
  - (a) Range = FoodPro value times servings (snapped to 0.5 steps), half-width 15% with a depth region of confidence 0.6 or more, else 25%, plus 15% times (1 - confidence), at most 50%. Unlisted items take the model's own range widened to at least plus or minus 40% and carry rough: true. Identical dishes across halls become one candidate that lists every hall.
  - (b) Ask the model for a range for every item.
  - (c) A fixed plus or minus 25% for everything.
- Decision: (a).
- Evidence: server/stezu_server/scan.py (`spread`, `span`, `widen`, `candidates`), server/Tests/test_scan.py.
- Reverse if: meals logged against weighed portions show the truth outside the range more than about 1 time in 5, or the ranges come out much wider than the observed error.
## D-038 Work items are user stories, each proven by a UI test on the simulator

- Status: proposed, 2026-10-25 (infra/v1-stories).
- Problem: every gate passed on the first night, yet the app on the phone showed three blank cards that could not be tapped. Nothing checked what a person can do on a screen.
- Given: features.json listed engineering units with unit tests. The ios CI job ran only AppTests and was advisory. Night cards run on a Linux VM with no simulator. D-032 to D-035 define v1 as tracking only across Workout, Food and Data.
- Constraints:
  - Unit tests alone break the link between "passes" and "usable": a view model can pass with no screen behind it.
  - A check that only runs on a Mac breaks for night cards, which have no simulator; it has to run in CI.
  - A required macOS job adds roughly 10 to 15 minutes to every PR, which slows docs-only merges.
- Options:
  - (a) Keep engineering features and add a manual phone check each morning.
  - (b) User stories whose steps an XCUITest drives on a CI simulator, with named screenshots kept as artifacts, and the ios job required.
  - (c) Image snapshot tests compared against stored references.
- Decision: (b). features.json schema 2 keeps F-001 to F-010 unchanged as `kind: engine` and adds S-001 to S-026 as `kind: story` (3 shell, 9 workout, 8 food, 6 data), each sized for one card, ordered shell first so the three areas can then run in parallel. `--flip` needs the story's dependencies to pass and its tests and screenshot names to exist; the ios check runs the UI tests and fails when a passing story's screenshots are missing. `ios` becomes a required check next to `linux-core` once it passes on this PR.
- Evidence: features.json, scripts/check-features.py, scripts/export-screenshots.py, .github/workflows/ci.yml, App/UITests/SmokeUITests.swift.
- Reverse if: the ios job is too slow or flaky to gate merges (then run the UI tests nightly on main instead), or a story passes in CI and still fails on the phone, which would mean the fakes hide too much.

## D-039 A -uitest launch argument swaps every outside dependency for a fake, chosen once at launch

- Status: proposed, 2026-10-25 (infra/v1-stories).
- Problem: UI tests on a CI simulator have no camera, no Health data, no server and no network, and the v1 screens need all four.
- Given: core already reaches the dining menu through an injected transport (D-020). XCUITest drives the app as a separate process. SwiftUI views can read values from the environment.
- Constraints:
  - Fakes that exist only in a test target break, because XCUITest cannot inject objects into the app process.
  - A separate test build configuration with `#if` breaks the one-project, one-scheme setup cards rely on and doubles build time.
  - Fixture data resembling Isaac's breaks D-034.
- Options:
  - (a) A launch argument that the app reads at start to pick fakes, passed down as one environment value.
  - (b) A UITest build configuration that compiles fakes in with `#if`.
  - (c) A mock HTTP server and seeded Health data on the CI simulator.
- Decision: (a). `AppEnvironment.fromLaunch()` reads `-uitest` and picks an in-memory store, `FakeHealthStore`, `FakeVMTransport` and `FixturePhotoSource`; `-uitest-scenario`, `-uitest-offline`, `-uitest-persist` and `-uitest-reset` cover seeded data, offline queues and resume after relaunch. Views read `\.appEnvironment`. The protocols and core fakes (`HealthStore`, `VMTransport`) live in StezuCore so core tests use them too. The live app uses `HealthKitStore`, and `UnconfiguredVMTransport` until Settings has a server. The fakes ship in the app binary but are reachable only through the launch argument.
- Evidence: App/Sources/AppEnvironment.swift, App/Sources/PhotoSource.swift, App/Sources/UITestFixtures.swift, Packages/StezuCore/Sources/StezuCore/HealthStore.swift and VMTransport.swift, App/UITests/UITestSupport.swift.
- Reverse if: the app ships to anyone but Isaac (then strip the fakes with `#if DEBUG`), or a bug that the fakes hide reaches the phone more than once.

## D-040 Project files change only on infra/* branches

- Status: proposed, 2026-10-25 (infra/v1-stories).
- Problem: v1 needs an entitlement, Info.plist keys, a widget extension and a UI test target, but G3 forbids cards from touching project files, and that rule is what stops unattended cards from granting themselves capabilities or relaxing their own gates.
- Given: G3 failed any branch that changed an entitlements file or mentioned entitlements in project.yml, and treated every non-main branch as a card. Cards run unattended; Isaac reviews in the morning. A server agent builds server/ in parallel.
- Constraints:
  - Letting cards edit project.yml, scripts/ or CI breaks the gates' independence: a card could loosen the gate that judges it.
  - Card budgets (300 lines, 12 files) break infra PRs such as this one (about 1,700 non-test lines in 23 files, most of it features.json).
  - Checking project.yml's whole text for "entitlements" breaks every card once the app legitimately has an entitlement.
- Options:
  - (a) Branch kind decides: infra/* may change project files and has no size budget; every other branch is a card that may not.
  - (b) A per-PR label that unlocks project files.
  - (c) Isaac makes every project change by hand.
- Decision: (a). Card branches may not change *.entitlements, project.yml, scripts/, .github/, Package.swift, Info.plist or *.xcodeproj. infra/* may, without a size limit, and G2 lets it restructure features.json. The signing check now looks only for a team, identity or profile. G5 runs server/run_tests.sh when it exists.
- Evidence: scripts/diff-budget.sh, scripts/check-features.py, scripts/gate-linux.sh, AGENTS.md.
- Reverse if: a card ever pushes an infra/* branch (then require Isaac's approval on infra PRs), or cards are blocked for a whole night by a project change they needed.

## D-041 The shell owns the current area and adds the bottom nav around every area screen

- Status: proposed by night agent, 2026-10-25 (S-001).
- Problem: every area screen needs the same three bottom circles that switch areas in one tap, and the area views are being rebuilt in parallel by other cards.
- Given: AppShell already holds the current area as an optional `Area` (nil is Home). Area views take only a `goHome` closure. SwiftUI can attach a bottom bar to any view with `safeAreaInset`.
- Constraints:
  - Putting the nav inside each area view or inside AreaScaffold breaks parallel cards: every area card would need a new parameter and would conflict on rebase.
  - A TabView breaks the design (system tab bar, no Home screen above it) and adds its own navigation state next to the shell's.
- Options:
  - (a) AppShell wraps the active area view with `safeAreaInset(edge: .bottom)` holding `BottomNav`, which sets the shell's area.
  - (b) AreaScaffold draws the nav and reads an "open area" closure from the environment.
  - (c) A TabView with custom-styled items.
- Decision: (a). The area state stays in one place; area views never navigate and are unchanged. Circles are "nav.circle.<area>" with accessibility value "active" or "inactive".
- Evidence: App/Sources/AppShell.swift, App/Sources/BottomNav.swift, App/UITests/ShellNavigationUITests.swift (wt/S-001).
- Reverse if: an area needs a screen without the bottom nav (a full-screen logger or camera), in which case the area view should report that to the shell.

## D-042 Templates live in one library file; a newer bundled seed is upserted by key, skipping edited templates

- Status: proposed by night agent, 2026-10-25 (S-003).
- Problem: the app ships a generic program that later versions may improve, while the user edits templates and will import his own (S-011); a seed update must not undo either, and must not touch workout history.
- Given: D-034 (the repo holds only a generic seed). project.yml bundles every non-Swift file under App/Sources as a resource, and there is no App/Resources source path; card branches cannot change project.yml (D-040). No session store exists yet. Core tests run on Linux without the app bundle.
- Constraints:
  - Replacing all templates whenever the seed changes breaks edits and imports.
  - Applying the seed only on first launch breaks seed improvements for existing installs.
  - Putting the seed in App/Resources breaks bundling (not a source path) until an infra PR adds it.
  - Keeping history inside the template library couples a seed update to history.
- Options:
  - (a) A `TemplateLibrary` (seedVersion, templates in rotation order, editedKeys) saved as one JSON file; at launch a seed with a higher seedVersion replaces or appends templates by key unless the key is in editedKeys. Templates not in the seed stay.
  - (b) A per-template seed version compared one by one.
  - (c) Reseed from scratch and replay a log of user edits.
- Decision: (a). The seed is App/Sources/Workout/PrebuiltWorkouts.json; core tests read the same file from the repo. `-uitest` memory storage keeps no file, so each launch starts from the seed. The rotation is `next(after: lastTemplateKey)`, the first template when nothing was done; until sessions are stored the app passes nil.
- Evidence: Packages/StezuCore/Sources/StezuCore/WorkoutTemplate.swift, App/Sources/Workout/WorkoutTemplateStore.swift, App/Sources/Workout/PrebuiltWorkouts.json, Packages/StezuCore/Tests/StezuCoreTests/WorkoutTemplateTests.swift (wt/S-003).
- Reverse if: the user wants a seed fix applied to a template he edited (then offer a per-template "reset to seed"), or templates move into a shared store with sessions.

## D-043 Server settings live in a store on AppEnvironment, and Save rebuilds the app's VM transport

- Status: proposed by night agent, 2026-10-25 (S-002).
- Problem: the app needs one server address and token, typed once on the device, and every server call after a save must go to that server with that token, while `-uitest` launches and the repo never hold a real address or token.
- Given: AppEnvironment is chosen once at launch and passed down as `\.appEnvironment`; `live()` used UnconfiguredVMTransport. The Keychain needs no entitlement for the app's own items. AppTests assert that a fresh live launch has UnconfiguredVMTransport.
- Constraints:
  - Writing the token to UserDefaults breaks the story (token in the Keychain) and leaks it into device backups in clear.
  - Reading the settings inside each server client breaks the fakes: tests and `-uitest` would need a Keychain, and every client would repeat the lookup.
  - A transport that reads the store on every call breaks `is UnconfiguredVMTransport` checks and hides "not configured" behind a configured-looking type.
- Options:
  - (a) A `ServerSettingsStore` on AppEnvironment (UserDefaults plus Keychain live, memory in `-uitest`); `live()` builds the transport from the saved settings, and Save calls `AppEnvironment.useServer`, which replaces `vmTransport` in the app's `@State` environment (a no-op under `-uitest`, which keeps FakeVMTransport).
  - (b) A wrapping transport that reads the store on each send.
  - (c) Settings in `@AppStorage` read directly by the views.
- Decision: (a). `ServerSettings.transport()` returns URLSessionVMTransport (path after the base URL's path, `Authorization: Bearer`, network errors as `unreachable`) only when the address is an http(s) URL with a host and the token is non-empty, else UnconfiguredVMTransport. `ServerConnection` maps a call's outcome to display text; not configured reads "Set up the server in Settings". Test connection uses the saved settings, not unsaved typing.
- Evidence: App/Sources/Settings/ServerSettings.swift, App/Sources/Settings/SettingsView.swift, App/Sources/AppEnvironment.swift, App/Tests/ServerSettingsTests.swift, App/UITests/ServerSettingsUITests.swift (wt/S-002).
- Reverse if: a background task or extension needs the server without the app running, in which case the token moves to a shared Keychain access group (an infra change).

## D-044 The shutter writes the photo to a local file before anything touches the network

- Status: proposed by night agent, 2026-10-25 (S-012).
- Problem: a meal photo must survive a failed or slow upload, a dead connection and an app relaunch, and the stories that send it to the server (S-013 on) are built in parallel.
- Given: AppEnvironment already picks a `StorageMode` (disk, memory, temporary folder) at launch. No app store exists yet. The server's POST /scan is idempotent on meal id plus photo hash (server/README.md).
- Constraints:
  - Holding the photo only in view state breaks the offline story: a relaunch or a failed call loses the meal.
  - A database or a new package breaks the no-new-dependencies rule on a card branch.
  - Starting the upload inside the shutter call breaks the ordering S-012 asks for and makes the save depend on the network.
- Options:
  - (a) An actor `MealCaptureStore` in AppEnvironment that writes `<id>.jpg` and `<id>.json` into one folder per storage mode; `MealCapture.shutter()` captures and saves only, and matching starts later from the saved meal.
  - (b) Core Data or SwiftData.
  - (c) Keep the photo in memory and save it after the server answers.
- Decision: (a). Disk mode uses Application Support/meals, `-uitest-persist` uses the temporary store folder's meals/, and memory mode a fresh temporary folder per launch, so there is one code path. The live camera (`LiveCameraPhotoSource`) asks for access when Food opens; if denied, the screen explains how to turn it on in Settings.
- Evidence: App/Sources/Food/MealCapture.swift, App/Sources/Food/FoodView.swift, App/Sources/AppEnvironment.swift, App/Tests/MealCaptureTests.swift (wt/S-012).
- Reverse if: meals need queries the files cannot answer cheaply (history by day, sync state), at which point a real store replaces the folder behind the same actor.

## D-045 The logger is one Codable value saved whole after every log or undo

- Status: proposed by night agent, 2026-10-25 (S-004).
- Problem: a set must be stored the moment it is logged, undo must take back exactly the last set even after the card moved to the next exercise, and the prepared numbers must survive with it.
- Given: `WorkoutSession` (D-026) keeps sets per exercise, not one global order. No session store exists yet; S-008 adds Finish and Health. Memory storage under `-uitest` keeps no files (D-039).
- Constraints:
  - Undoing by the latest `loggedAt` breaks when two sets share a timestamp.
  - Saving only on Finish breaks "saved at that moment" and loses sets if the app is killed.
  - A database or new dependency breaks rule 7 on a card branch.
- Options:
  - (a) `SetLogger` in core: template, session, the card's exercise, weight, reps, bodyweight flag and a log order of exercise indices; Codable and saved whole as active-workout.json by `WorkoutSessionStore` on every change.
  - (b) Append-only event log (logged / undone) replayed at load.
  - (c) Keep state in the view and save only the session.
- Decision: (a). The view saves through `.onChange(of: logger)`. Undo pops the log order, removes that exercise's last set and puts its numbers (and bodyweight state) back on the card. Bodyweight logs `pounds == nil`. Steppers clamp weight to [one step, 2000] and reps to [1, 100]; the weight step is the exercise's `weightStep`, else 5 lb. The prefilled weight is the exercise's `startPounds` (the seed gives barbell lifts the 45 lb empty bar; seedVersion 2), else "--" with Log off until a weight or BW is chosen. Nothing yet reads the saved file back (resume is later work).
- Evidence: Packages/StezuCore/Sources/StezuCore/SetLogger.swift, App/Sources/Workout/WorkoutSessionStore.swift, App/Sources/Workout/WorkoutLoggerView.swift, App/Sources/Workout/PrebuiltWorkouts.json (wt/S-004).
- Reverse if: sessions move into a shared store with history (S-005/S-008), or the file grows enough that whole-file writes per set become slow.

## D-046 Sessions carry their template key, and the logger takes its last numbers once at Start

- Status: proposed by night agent, 2026-10-25 (S-005).
- Problem: last-session numbers must come from the last session of the same template when there is one, and from any template otherwise, but a stored session did not say which template it came from.
- Given: `WorkoutHistory.lastSession` (D-026) finds the latest earlier session with an exercise. `SetLogger` (D-045) is Codable and saved whole. No store of finished sessions exists yet; S-008 adds Finish.
- Constraints:
  - Matching sessions to templates by their exercise names breaks when two templates share an exercise, which is exactly the case to handle.
  - Looking history up in the view on every render breaks the "view reads only the environment" rule and recomputes per set.
  - A non-optional key breaks decoding of sessions saved before this card and empty workouts.
- Options:
  - (a) `WorkoutSession.templateKey: String?`, set by `SetLogger`; `TemplateHistory.lastSession` filters by key and falls back to all sessions.
  - (b) A separate index from session start date to template key.
  - (c) Keep only the latest numbers per (template, exercise) in a small table.
- Decision: (a). `SetLogger.init(template:startedAt:history:)` computes `last` for every template exercise once and keeps it in the saved value; an exercise is prefilled from its last session's first set (a bodyweight set prefills BW), else from `startPounds` and the low rep, else "--" with Log off. The fallback applies per exercise: when no session of this template had it. The card's "Last 60 x 8, 7d ago" line uses the last session's set at the same position, or its last set. History reaches the view as `AppEnvironment.workoutHistory`: empty in the live app until a session store exists, synthetic under `-uitest-scenario workout-history`.
- Evidence: Packages/StezuCore/Sources/StezuCore/TemplateHistory.swift, SetLogger.swift, WorkoutSession.swift, App/Sources/AppEnvironment.swift, App/Sources/UITestFixtures.swift (wt/S-005).
- Reverse if: templates get renamed keys or merged, so the key no longer identifies "the same workout", or history grows large enough that per-Start scans are slow.

## D-047 Device check: free-account signing works; what Zepp writes to Apple Health

- Status: decided by Isaac's device test, 2026-10-25. Answers the open items in D-008 and D-009.
- Signing: the HealthKit entitlement and the RestActivity extension both signed with his free personal team, installed and ran on his iPhone.
- Zepp (Helio Strap) writes: weight, heart rate, sleep, activity, a temperature metric, blood oxygen and respiratory rate. HRV was not on his list and may be absent.
- Consequences:
  - The weight trend counts only weigh-ins written by Stezu, because Zepp also writes weight (probably a static profile value). Other body-mass sources appear on Sources.
  - S-027 adds blood oxygen, respiratory rate and temperature as context rows.
  - The Data screen and Sources expect HRV to be missing.

## D-048 Export to Hermes: the phone sends its data to the VM server's own database

- Status: decided by Isaac ("add the feature to export the data to hermes"), 2026-10-25. The mechanism is proposed.
- Problem: Apple Health data can only be read on the phone, but Hermes runs on the VM and needs the data to answer questions about it later.
- Choice:
  - The app sends raw samples (with HealthKit UUIDs), its own workouts and sets, and its meals to POST /sync on the Stezu server over Tailscale with the device token.
  - The server stores them in a SQLite database on the VM, outside the repo.
  - Hermes reads that database read-only.
  - No model provider sees this data; /sync never calls Claude.
- Rejected:
  - Reviving Karina's Postgres store: frozen by D-012. An adapter can copy into it later if a loop needs it.
  - Health Auto Export: paid, and a second path for the same data.
  - iCloud: not available on a free account.
- Reverse if: the VM database becomes the bottleneck for an analysis loop.

## D-049 Meal totals are summed on the phone from the item ranges, and an unknown range makes the total unknown

- Status: proposed by night agent, 2026-10-25 (S-013).
- Problem: the match sheet needs meal totals as ranges, and S-015 will change servings, remove and add items, so the totals must follow the list; some items can come back with a null kcal or protein end.
- Given: POST /scan returns per-item `kcal` and `protein_g` as `{low, high}` (either end may be null) plus server `totals`. Rule 5: absent is not zero.
- Constraints:
  - Showing the server's `totals` breaks S-015: after any edit they are stale, and recomputing only after edits gives two sources for one number.
  - Treating a null end as 0 breaks rule 5 and understates the meal.
  - Failing the whole decode on one null end breaks the photo: one bad item would hide every match.
- Options:
  - (a) `FoodRange.total` sums lows and highs of the items on the phone; an item without a range makes the total nil ("--"). Ranges decode leniently, so a range with a null end is nil for that item only.
  - (b) Show the server totals and recompute only after edits.
  - (c) Sum the known items and ignore unknown ones.
- Decision: (a). The server `totals` field is decoded by nobody.
- Evidence: Packages/StezuCore/Sources/StezuCore/FoodRange.swift, Packages/StezuCore/Sources/StezuCore/PhotoMatch.swift, FoodRangeTests, PhotoMatchClientTests (commit on wt/S-013).
- Reverse if: items often lack one range, so totals are "--" too often; then show a partial total marked as partial.

## D-050 In -uitest the scan route is held unless the photo-match scenario is on

- Status: proposed by night agent, 2026-10-25 (S-013).
- Problem: S-012's UI test asserts the "Matching..." sheet after the shutter, and S-013's asserts the matched items; with an instant fake reply the first state is gone before the test can see it.
- Given: FakeVMTransport answers from a route table at once. UI tests pick fixtures through `-uitest-scenario`.
- Constraints:
  - Answering /scan in every -uitest launch breaks S-012's test (a race it would lose).
  - Leaving /scan unrouted (404) breaks it too: the sheet turns to "Could not match".
  - Editing S-012's test to pass a flag changes another story's test.
- Options:
  - (a) FakeVMTransport takes a set of held routes that never answer until the task is cancelled; -uitest holds POST /scan unless the scenario is "photo-match".
  - (b) A fixed fake delay on /scan.
  - (c) Change S-012's UI test to launch offline.
- Decision: (a). Deterministic, and a held call is what a slow server looks like.
- Evidence: Packages/StezuCore/Sources/StezuCore/VMTransport.swift, App/Sources/UITestFixtures.swift, App/Sources/AppEnvironment.swift (commit on wt/S-013).
- Reverse if: a later story needs the held state and the answer in one launch; then add a fake call that releases held routes.

## D-051 The rest lives in the logger view, and its Live Activity and notification sit behind one stateless protocol

- Status: proposed by night agent, 2026-10-25 (S-006).
- Problem: after a set is logged, a rest must count down at that exercise's template rest, take +15/-15/Skip, and keep a lock-screen Live Activity and a zero notification in step, while tests run without ActivityKit or notification prompts.
- Given: `RestTimer` (D-027) stores a start time and reads an injected clock. `SetLogger` (D-045) is saved whole after every change. RestActivityAttributes in App/Shared carries `startedAt`, `endsAt` and a set label; the widget counts down between them by itself.
- Constraints:
  - Putting the rest in `SetLogger` breaks its Codable save (the timer holds a clock closure) and would resume a stale rest after a relaunch.
  - Keeping the current `Activity` object in the app breaks Sendable `AppEnvironment` and loses it if the view goes away.
  - Pushing a Live Activity update every second breaks the system's update budget; the widget's own countdown needs only start and end.
- Options:
  - (a) A `RestActivityController` value in the logger view's state wraps `RestTimer` and calls `RestAlerts` (start, update, end) on log, adjust, skip and zero; `LiveRestAlerts` finds its activities through `Activity.activities` and its notification by id.
  - (b) An observable rest object on `AppEnvironment` shared by every screen.
  - (c) Rest fields added to `SetLogger` and saved with it.
- Decision: (a). `RestTimer` gained `adjust(by:)` (moves only the end, never below 0, which ends the rest), `skip()` and `endsAt`. Each Log starts a new rest at the logged exercise's `restSeconds` (0 starts none). The controller calls `start` once, `update` on each adjust with the same start and the new end, and `end` on Skip or when a `.task` keyed on the end time wakes at zero. `LiveRestAlerts.start` ends older activities, requests one when activities are enabled, and replaces the single pending notification (id "rest.end"); failures are ignored, so the in-app countdown always works. `-uitest` and previews use `FakeRestAlerts`, which records the calls.
- Evidence: Packages/StezuCore/Sources/StezuCore/RestTimer.swift, App/Sources/Workout/RestActivityController.swift, App/Sources/Workout/LiveRestAlerts.swift, App/Sources/Workout/WorkoutLoggerView.swift, App/Sources/AppEnvironment.swift (wt/S-006).
- Reverse if: the rest must survive leaving the logger or a relaunch, or a screen other than the logger must show it; then move it to (b) and save its start and end.

## D-052 An imported program file is validated whole, then each template is upserted by key and marked edited

- Status: proposed by night agent, 2026-10-25 (S-011).
- Problem: a program file picked on the phone has to add or replace templates without touching history, and a bad file must leave the library exactly as it was; a later bundled seed must not undo an import.
- Given: TemplateLibrary (D-042) holds templates by key, applies seeds only when their version is newer, and skips keys in `editedKeys`. Sessions are stored apart from templates. The file uses the seed's format, so it also carries a seedVersion.
- Constraints:
  - Applying templates while validating breaks "changes nothing": a file that fails on its third template would leave the first two in.
  - Treating the file as a seed breaks repeat imports: its seedVersion would have to beat the bundled one, and an older-numbered file would be ignored.
  - Leaving imported keys unprotected breaks the import on the next app update, when a newer seed overwrites the same keys.
- Options:
  - (a) Decode and check the whole file first (`ProgramImport.parse`: JSON shape, at least one template, unique non-empty keys, names, sets >= 1, a valid rep range, rest >= 0), then `edit` each template, which upserts by key and adds it to `editedKeys`. The file's seedVersion is ignored.
  - (b) Upsert as a seed with a forced version.
  - (c) Keep imported templates in a second library layered over the seed.
- Decision: (a). `TemplateLibrary.importProgram(_:)` returns the count or a `ProgramImport.Failure` whose message the screen shows after "Import failed."; the app saves the library only on success. The picker is `AppEnvironment.programFilePicker`: the Files picker (`.fileImporter`, security-scoped read) live, a generic fixture in `-uitest` (`program-invalid` scenario for a broken file).
- Evidence: Packages/StezuCore/Sources/StezuCore/ProgramImport.swift, App/Sources/Workout/ProgramFilePicker.swift, App/Sources/Workout/WorkoutView.swift, App/Sources/AppEnvironment.swift (40f9d5e).
- Reverse if: Isaac wants an import to replace the whole program (remove templates the file lacks), or a seed fix should reach an imported template.

## D-053 /sync keys samples by HealthKit UUID with tombstones and records by newest updated_at, in its own SQLite file

- Status: proposed by the server/sync session, 2026-10-25.
- Problem: the phone will send the same data more than once (retried batches, a reinstall's 90-day backfill, a queue replayed out of order), and HealthKit reports deletions separately, before or after the sample they delete reaches the server. Hermes also needs daily numbers from sources that overlap.
- Given: D-048 (the phone POSTs to the VM; Hermes reads read-only). HealthKit samples never change and carry a UUID; Stezu records have their own ids and do change. Apple Health merges overlapping sources by a priority list that HealthKit does not expose. The service runs under a 300 MB memory cap, and server.sqlite3 is a disposable cache.
- Constraints:
  - Deleting a row on an HKDeletedObject breaks replay: an older batch sent again would bring the sample back.
  - Rejecting a whole batch for one bad item breaks the app's retry queue: that batch would fail forever.
  - Keeping only UTC breaks day-keyed views, because the sqlite3 CLI Hermes uses has no time-zone database; keeping only local time breaks ordering across DST and travel.
  - Writing health rows into the cache file breaks the cache's disposability: clearing it would erase history.
- Options:
  - (a) A separate health.db; samples `INSERT ... ON CONFLICT (uuid) DO NOTHING`; a deletion sets `deleted_at` or inserts a tombstone row; records upsert only when `updated_at` is newer; per-item validation with a `rejected` count; UTC plus precomputed local columns; SQL views for daily numbers.
  - (b) As (a), but hard deletes and last-write-wins on samples.
  - (c) Store each batch as a JSON blob and derive tables later.
  - (d) Karina's Postgres store: frozen by D-012.
- Decision: (a). Batches hold at most 5,000 items and 24 MiB of JSON (gzip allowed). Day keys use `STEZU_HEALTH_TZ` (default America/New_York) and are recomputed when it changes. `daily_steps` and `sleep_nights` take the largest single source per day or night and also expose the raw sum or the per-source rows.
- Evidence: server/stezu_server/health.py, server/stezu_server/app.py, server/Tests/test_sync.py, server/README.md (server/sync). A 5,000-sample batch is stored in about 0.15 s on the VM; a replay of it counts 5,000 duplicates.
- Reverse if: Hermes needs Health's exact merged totals (then the app sends daily `HKStatisticsCollectionQuery` sums as records), or the database grows to where `/sync/status` takes more than about a second.

## D-054 Data asks Health once, on the first Connect tap, and remembers it in a flag; reads that return nothing are absent

- Status: proposed by night agent, 2026-10-25 (S-020).
- Problem: Data must not ask for Health access at launch, must ask once when Isaac taps Connect, and must not show the empty state again; afterwards Sources has to tell "no data" apart from a real count.
- Given: HealthKit shows its sheet only for types not yet asked about and never says whether a read was denied: a denied read returns no samples. The `-uitest` launch uses FakeHealthStore, which counts requests.
- Constraints:
  - Deciding from HealthKit's authorization status breaks for reads: it is only reported for writes, so the empty state could return.
  - Asking at launch breaks the story ("nothing is asked at app launch").
  - Showing 0 samples for a type with none breaks rule 5 and hides a denied read.
- Options:
  - (a) `HealthConnection` keeps a "health.connected" flag (UserDefaults live, memory in -uitest), set after `requestAuthorization` returns; `connect` is a no-op once set. A type with no sample ever is absent ("--") with the hint to turn the read on.
  - (b) Ask on every Data open and let HealthKit suppress repeats.
  - (c) Probe each type with a read to guess access.
- Decision: (a). A throw from the sheet leaves the flag unset, so Connect can be tried again.
- Evidence: App/Sources/Data/HealthConnection.swift, App/Sources/Data/DataView.swift, Packages/StezuCore/Sources/StezuCore/HealthSources.swift, AppTests HealthConnectTests, HealthSourcesTests (commit b06a4dd on wt/S-020).
- Reverse if: a later version adds types; then the flag must become a version number so the sheet asks again for the new types only.

## D-055 A swap lives in the session's logger by template slot; custom exercises are keyed once from their name and saved apart from the bundled list

- Status: proposed by night agent, 2026-10-25 (S-007).
- Problem: a swapped exercise must replace the one on the Log card for this session only, leaving the template as it was, and a custom exercise needs a key that never changes so history and later picks find it.
- Given: `SetLogger` (D-045) holds the template and the session and is saved whole after every change; sets are stored by exercise name. `TemplateLibrary` keeps templates and marks edited ones. The library list ships in the app (D-034: generic only).
- Constraints:
  - Writing the swap into the template breaks "this session only" and marks the template edited, so later seeds skip it.
  - Undo looking up the slot's current exercise breaks once a slot is swapped after a set was logged (the set is stored under the old name).
  - Keying custom exercises by list position or a random id breaks merging with a newer bundled list and is not reproducible in tests.
- Options:
  - (a) `SetLogger.swaps` maps a template slot to the swapped-in exercise (keeping the slot's sets and reps, taking the library's rest); undo records the slot and the exercise name; custom exercises get "custom-<name slug>" (with -2, -3 on a clash) and are saved to custom-exercises.json beside the active workout, merged after the bundled ExerciseLibrary.json on load.
  - (b) A copy of the template edited in place for the session.
  - (c) Custom exercises keyed by UUID and stored inside the template library file.
- Decision: (a). The swapped exercise is prefilled from its last session of any template, else with no weight ("--"). A key starting with "custom-" is what marks an exercise custom.
- Evidence: Packages/StezuCore/Sources/StezuCore/ExerciseLibrary.swift, Packages/StezuCore/Sources/StezuCore/SetLogger.swift, App/Sources/Workout/ExerciseLibraryView.swift, App/Sources/Workout/WorkoutLoggerView.swift (wt/S-007).
- Reverse if: a swap should be offered as a template change too ("always use this"), or custom exercises must sync between devices; then add an explicit template edit and a UUID beside the slug key.

## D-056 Finish keeps the session on the phone first-class and writes Health once per external id

- Status: proposed by night agent, 2026-10-25 (S-008).
- Problem: Finish must close the logger in one tap, write the session to Apple Health as a strength workout, keep the session when that write is denied or fails, and never write an empty workout or the same workout twice.
- Given: `SetLogger` (D-045) holds the session and is saved to active-workout.json after every change. `HealthStore` is the only way to HealthKit; `-uitest` uses `FakeHealthStore`. No finished sessions were stored before this card.
- Constraints:
  - Making the saved session depend on the Health write breaks "the session still saves" whenever Health is denied.
  - A random id per write breaks retry safety: a second attempt would add a second workout.
  - Showing 0 for a week without sessions breaks "absent is not zero".
- Options:
  - (a) `WorkoutFinish.finish` (core) discards a session with no sets (nil, no write), otherwise calls `saveStrengthWorkout(start:end:externalID:)` with an id derived from the start time and returns a `FinishedWorkout` with `inHealth` true or false; the app appends it to finished-workouts.json either way.
  - (b) Queue the Health write and keep a pending state until it lands.
  - (c) Store sessions only in Health and read them back.
- Decision: (a). The external id is "stezu.workout.<start in ms>", so the same session always maps to one id; `HealthKitStore` asks for permission if it was never asked, skips the write when a workout with that `HKMetadataKeyExternalUUID` exists, and builds it with `HKWorkoutBuilder` (traditional strength training, no energy samples). The Workout screen closes the logger at once, clears active-workout.json, and adds the row after the write returns; the week (Monday to Sunday) shows sessions and working sets, "--" when there are none. Finished sessions also feed last-session numbers.
- Evidence: Packages/StezuCore/Sources/StezuCore/WorkoutFinish.swift, Packages/StezuCore/Sources/StezuCore/HealthStore.swift, App/Sources/Health/HealthKitStore.swift, App/Sources/Workout/FinishedWorkoutStore.swift, App/Sources/Workout/WorkoutView.swift (4253ed3).
- Reverse if: a "Not in Health" session must be retried automatically, or the app is killed between Finish and the write often enough to lose sessions; then save first with a pending state (b).
## D-057 Weigh-ins are body-mass samples Health credits to Stezu; the week's row reads them back from Health

- Status: proposed by night agent, 2026-10-25 (S-021).
- Problem: the Weight row needs a trend from Isaac's weigh-ins, but Health's body-mass type also holds other apps' samples (a strap writes its static profile weight), and the app has no local weight store.
- Given: F-001's `TrendWeight` (EWMA over irregular days). HealthKit credits every sample to the app that wrote it (source bundle id). Writes from Stezu carry com.ik301.stezuhealth. `HealthStore` is the only path to Health; FakeHealthStore in tests and -uitest.
- Constraints:
  - Mixing every body-mass source into the trend breaks the trend: a fixed profile weight pulls it toward a number nobody measured.
  - A separate local weigh-in store breaks single ownership: Health and the app could disagree, and weigh-ins from before a reinstall would vanish.
  - Showing 0 for a week with no weigh-ins breaks rule 5.
- Options:
  - (a) Save writes one body-mass sample through `HealthStore.saveBodyMass`; the row reads 90 days of body mass back and keeps only samples whose source bundle id is Stezu's (`WeeklyWeight.weighIns`), listing the apps it used. Other apps' samples show on Sources with their counts and only feed the stepper's prefill when Stezu has none.
  - (b) Keep weigh-ins in the app's own store and also write them to Health.
  - (c) Use every body-mass sample and let Isaac pick sources in a setting.
- Decision: (a). The week runs Monday to Sunday in the device calendar; with no Stezu weigh-in this week the trend, change and coverage are nil and show "--". The change is the trend now minus the trend at the end of last week (or this week's first weigh-in if there is none before).
- Evidence: Packages/StezuCore/Sources/StezuCore/WeeklyWeight.swift, HealthStore.swift, App/Sources/Data/WeightRow.swift, App/Sources/Health/HealthKitStore.swift, HealthStoreTests, WeighInTests, AppUITests WeightUITests (commit on wt/S-021).
- Reverse if: Isaac weighs in on a smart scale that writes to Health; then the allowed bundle ids become a setting (`weighIns(_:bundleIDs:)` already takes the set).

## D-058 Weekly context rows read per-day statistics and sleep stages from Health, keyed by day, and a day without data is a missing key

- Status: proposed by night agent, 2026-10-25 (S-022).
- Problem: steps, resting heart rate, sleep and HRV each need one weekly number and a coverage count, but several apps can write the same type (phone and strap both count steps, two apps can record one night), and a week with no readings must stay distinguishable from a week of zeros.
- Given: `HealthStore` is the only path to Health (FakeHealthStore in tests and -uitest). HealthKit's statistics collection query merges overlapping sources per bucket; raw sample queries do not. sleepAnalysis samples are stage intervals (in bed, awake, core, deep, REM, unspecified). The week runs Monday to Sunday (D-057).
- Constraints:
  - Summing raw step samples breaks the total: a phone and a strap counting the same walk double it.
  - Dating a night by its start date breaks nights that cross midnight, and summing every stage counts time in bed and awake.
  - Returning 0 for a day or week without data breaks rule 5, and HealthKit hides denied reads, so no data and no access must look the same.
- Options:
  - (a) `HealthStore.dailyValues` runs one statistics collection query in day buckets (sum for steps, discrete average for resting heart rate) and returns only days that have a value; `sleepIntervals` returns the stages; core turns them into `WeeklyStat`s (value nil when coverage is 0, confidence from coverage).
  - (b) Read raw samples for every type and dedupe sources in core by picking one app per type.
  - (c) Keep a local daily cache in the app, filled from Health in the background.
- Decision: (a). A night belongs to the day its stages end on, with anything ending after 18:00 counted toward the next day; asleep stages are merged as a union so two apps recording one night count once. HRV stays a median of raw readings, with the reading count as coverage. FakeHealthStore buckets by the current calendar and does not remove overlap.
- Evidence: Packages/StezuCore/Sources/StezuCore/WeeklyHealth.swift, HealthStore.swift, App/Sources/Health/HealthKitStore.swift, App/Sources/Data/WeeklyHealthRows.swift, WeeklyStatTests, SleepNightTests, AppUITests WeeklyHealthUITests (commit on wt/S-022).
- Reverse if: Isaac's strap writes sleep as one asleepUnspecified block while another app writes stages; then pick one sleep source per night instead of the union.

## D-059 Metric detail reads its 8 weeks from Health when it opens and buckets per-day values into Monday-first weeks; a day without a key is absent

- Status: proposed by night agent, 2026-10-25 (S-024).
- Problem: every overview metric has to open one detail with 8 weekly values, their coverage and each week's 7 days, but each metric is built differently (weight from the trend, steps and resting heart rate from daily statistics, sleep from nights, HRV from raw readings), and an empty day or week must not turn into 0.
- Given: `HealthStore.dailyValues`, `sleepIntervals` and `samples` (D-058), `TrendWeight.series` and Stezu-only weigh-ins (D-057), `WeeklyStat` with coverage and confidence, and Monday-to-Sunday weeks from `WeeklyStats.week`.
- Constraints:
  - A separate detail per metric breaks the story's one template and multiplies the code past the diff budget.
  - Keeping 8 weeks in a local cache breaks the rule that Health is the store for read types, and goes stale when another app writes late.
  - Filling missing days with 0 breaks rule 5 and the weekly means.
- Options:
  - (a) `MetricHistory.load` reads 8 weeks (plus the trend's 90-day lead-in for weight) when the sheet opens, turns them into a `[day start: value]` map, and one `history(...)` splits that into 8 weeks of 7 days, each week's value and coverage made by the metric's own `WeeklyStat` function. A day without a key is nil and shows "--".
  - (b) Call the overview's `WeeklyHealth.load` 8 times, once per week, and add a separate per-day read.
  - (c) A local cache of daily values filled in the background.
- Decision: (a). Weight's week value is the trend at its last weigh-in that week, with weigh-in days as coverage; HRV's day value is that day's median. Sources are the app names on the read samples; sleep intervals carry none, so sleep shows "From: --".
- Evidence: Packages/StezuCore/Sources/StezuCore/MetricHistory.swift, App/Sources/Data/MetricDetailView.swift, DataView.swift, MetricHistoryTests, AppUITests MetricDetailUITests (commit on wt/S-024).
- Reverse if: opening a detail is slow on the device (8 weeks of raw step samples for the source names); then read sources from `HealthSources` once and pass them in.
