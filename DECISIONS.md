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
