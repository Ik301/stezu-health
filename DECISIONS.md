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

## D-059 The app is called Ingest on the home screen; identifiers keep the StezuHealth name

- Status: decided by Isaac, 2026-10-25 (merged in PR #29; this record was dropped from that PR when it merged and is restored here).
- Problem: the app had no icon, and "Stezu Health" is the project's name, not a name for the thing on the home screen.
- Given: renaming the target, bundle ids or repo would break HealthKit authorization and the builds already installed on his phone.
- Options:
  - (a) Change only the display name and permission strings to Ingest; the target, bundle ids and repo stay StezuHealth; add a single 1024 px icon in an asset catalog.
  - (b) Rename everything to Ingest now.
  - (c) Keep "Stezu Health" until the name is final.
- Decision: (a). The icon is the Home screen's three stacked cards with the middle one inverted, in DESIGN.md's monochrome tokens.
- Evidence: project.yml (CFBundleDisplayName, usage strings), App/Sources/Assets.xcassets, design/AppIcon.svg, DESIGN.md; commit 7d02a7c.
- Reverse if: the name changes again (edit the display strings only), or Ingest goes to the App Store, where the bundle ids would have to be renamed before the first release.

## D-060 Metric detail reads its 8 weeks from Health when it opens and buckets per-day values into Monday-first weeks; a day without a key is absent

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

## D-061 History groups sessions into Monday-to-Sunday weeks when it opens, from the sessions themselves

- Status: proposed by night agent, 2026-10-25 (S-010).
- Problem: History must show weeks newest first with each week's sessions and working-set count, and a week with no session must not appear as a row of zeros, while sessions keep arriving from two places (seeded history and finished-workouts.json).
- Given: finished sessions live in finished-workouts.json (D-056) and the Workout screen already holds them with the seeded `workoutHistory`. The week runs Monday to Sunday (D-056, D-057). Every logged set counts as a working set (S-008).
- Constraints:
  - Storing weekly totals beside the sessions breaks when a session is added or a store is rewritten: the totals go stale.
  - Walking calendar weeks from the oldest session to today breaks rule 5: gap weeks would need a row, and the easy row is 0.
  - Using the calendar's own first weekday breaks the Monday start on a device set to Sunday.
- Options:
  - (a) `WeeklyHistory.weeks` buckets the sessions by the Monday of their week (`firstWeekday = 2`) each time History opens, so only weeks with a session exist; the exercise page filters the same sessions by name.
  - (b) Keep a weekly index file updated on each Finish.
  - (c) Enumerate every week back to the first session and hide the empty ones in the view.
- Decision: (a). History is a read-only sheet over `environment.workoutHistory` plus the finished sessions; nothing new is stored.
- Evidence: Packages/StezuCore/Sources/StezuCore/WeeklyHistory.swift, App/Sources/Workout/WorkoutHistoryView.swift, App/Sources/Workout/WorkoutView.swift, WeeklyHistoryTests, AppUITests WorkoutHistoryUITests (commit on wt/S-010).
- Reverse if: history grows to thousands of sessions and opening History lags; then cache the weeks and rebuild them on Finish.

## D-062 Strap context rows take the median of raw readings, and breathing and temperature are counted by night

- Status: proposed by night agent, 2026-10-25 (S-027).
- Problem: blood oxygen, respiratory rate and temperature need one weekly number and a coverage count each, but a strap writes them at night in uneven bursts, Health stores oxygen as a fraction, and an Apple Watch writes a different temperature type than a strap does.
- Given: `HealthStore.samples(of:since:)` returns raw samples with values in each type's unit (fraction, count/min, °F). Sleep nights already belong to the day they end on, with anything after 18:00 counted toward the next day (D-058). The week runs Monday to Sunday.
- Constraints:
  - A mean of raw readings breaks on bursts: one night with many readings outweighs the rest, and a single spike moves it.
  - Counting oxygen coverage in days breaks the strap's pattern of many readings a night; counting breathing and temperature by reading hides how many nights are covered.
  - Mixing wrist temperature (Watch) with body temperature (strap) in one median breaks the number, because the two sit at different levels.
  - Showing 0 with no samples breaks rule 5.
- Options:
  - (a) Median of every reading in the week; oxygen is scaled to percent and its coverage counts readings; respiratory rate and temperature are grouped into nights the same way as sleep and their coverage counts nights. Temperature uses body temperature, and wrist temperature only when no app wrote body temperature that week.
  - (b) Per-day statistics queries (discrete average) as S-022 does for resting heart rate.
  - (c) Pick one source app per type and average it.
- Decision: (a). Read access for oxygenSaturation, respiratoryRate, bodyTemperature and appleSleepingWristTemperature joins the one Connect request, and all four appear on Sources. Every value is nil, shown as "--", when its coverage is 0.
- Evidence: Packages/StezuCore/Sources/StezuCore/WeeklyHealth.swift, HealthSources.swift, App/Sources/Health/HealthKitStore.swift, App/Sources/Data/WeeklyHealthRows.swift, WeeklyStatTests, AppUITests WeeklyHealthUITests (commit on wt/S-027).
- Reverse if: Isaac's strap turns out to write only body temperature deviations, or a Watch and a strap both write temperature; then show the type in use beside the value, or let Sources pick one.

## D-063 A meal is pending until its scan reply is saved beside the photo; opening Food retries pending meals oldest first and never deletes one

- Status: proposed by night agent, 2026-10-25 (S-017).
- Problem: a photo taken without a connection (or before a server is set) must survive relaunches, show as pending rather than 0 kcal, and get matched later in capture order, without the queue ever dropping a meal.
- Given: the shutter already saves `<id>.jpg` and `<id>.json` before any network call (S-012), `PhotoMatchClient` sends POST /scan (S-013), and `VMTransport` throws `VMTransportError` when offline or unconfigured.
- Constraints:
  - A separate queue file or database breaks the single source of truth: it can disagree with the photos on disk after a crash.
  - Re-encoding `PhotoMatch` needs Codable on every food model, which adds lines past the diff budget.
  - A background retry timer or BGTask needs a capability (Info.plist key), ruled out on a card branch.
- Options:
  - (a) State from files: a meal with `<id>.scan` (the raw 200 reply) is matched, one without it is pending. `MealQueue.retry` walks pending meals oldest first; a `VMTransportError` ends the round, any other failure leaves that meal pending and moves on. Retries run when Food opens.
  - (b) A queue.json list of pending ids, rewritten on each change.
  - (c) Retry on a timer while the app is open.
- Decision: (a). Nothing in the queue deletes files. The newest meal matched in a round opens in the sheet. Today's line counts pending meals for the day and shows logged kcal as "--" until meals can be logged (S-015), never 0.
- Evidence: Packages/StezuCore/Sources/StezuCore/MealQueue.swift, PhotoMatch.swift (`scanReply`), App/Sources/Food/MealCapture.swift, PhotoMatchSheet.swift, FoodView.swift, MealQueueTests, AppTests MealQueueStoreTests, AppUITests OfflineQueueUITests (commit on wt/S-017).
- Reverse if: meals must match while Food stays closed (retry from the app's scene phase instead), or the queue grows large enough that reading every reply on open is slow.

## D-064 The saved logger is the resume point; idle time runs from its last set, and an idle session is finished, not resumed

- Status: proposed by night agent, 2026-10-25 (S-009).
- Problem: a workout must survive the app being closed mid-session and reopen on the same exercise with its sets, while a session left open for hours must not stay open forever or end at the moment the app happens to be reopened.
- Given: `SetLogger` (D-045) is Codable, holds the session, the card's exercise, the undo order and swaps, and is written to active-workout.json after every change. `WorkoutFinish.finish` (D-056) writes Health once per external id and keeps the session either way.
- Constraints:
  - Rebuilding the logger from the session alone breaks undo and swaps, which live only in the logger.
  - Ending an idle session at launch time breaks its duration in Health (a 40-minute session would read as many hours).
  - Starting a new session over a saved one breaks "a set is stored the moment it is logged": the new logger overwrites the file.
- Options:
  - (a) `SessionResume.atLaunch` (core) reads the saved logger: within the idle limit (default 3 hours, `SessionResumeConfig`) it comes back unchanged as Resume; past it, a session with sets is closed through `WorkoutFinish.finish` ending at its last set, and one with no sets is dropped. Idle time runs from the last set, else from the start.
  - (b) Save only the session and rebuild a logger on resume.
  - (c) Ask on launch whether to resume or end an old session.
- Decision: (a). The Workout screen runs the check each time it loads with no logger open, so it also offers Resume after leaving the area mid-session. Resume replaces the black card and passes the saved logger to the logger view in one tap. Starting any other workout while Resume is offered first finishes the saved one at its last set and clears the file.
- Evidence: Packages/StezuCore/Sources/StezuCore/SessionResume.swift, App/Sources/Workout/WorkoutView.swift, App/Sources/Workout/WorkoutLoggerView.swift, SessionResumeTests, AppUITests SessionResumeUITests (commit on wt/S-009).
- Reverse if: the check must also run while the app stays in memory for hours (a scene-phase hook), or Isaac wants to keep a long session open; then raise `idleLimit` or ask (c).

## D-065 A search result becomes an item at 1 serving with a range around its one per-serving value; a text estimate keeps the server's rough range

- Status: proposed by night agent, 2026-10-25 (S-014).
- Problem: GET /search gives dining and packaged results as one kcal and protein number per serving, while the item list (S-013) shows only ranges and its totals sum ranges. The text estimate already comes as a range, and the list must still tell it apart as rough.
- Given: server/stezu_server/search.py: dining results carry `kcal`/`protein_g` numbers and every hall; Open Food Facts and USDA results carry `per_serving`; the estimate carries `{low, high}` widened to at least plus or minus 40% and `rough: true`. D-037 gives a photo of a listed item without depth plus or minus 25% at full confidence. `MatchedItem` is the item list's row type.
- Constraints:
  - Showing the single number breaks the item list's rule of ranges only and makes a pick look surer than a photo.
  - Widening on the server breaks the contract (server/ is out of bounds for cards).
  - Reading a missing number as 0 breaks rule 5.
- Options:
  - (a) `FoodSearchClient` decodes each result straight into a `MatchedItem` at 1 serving: a number becomes plus or minus 25% (`pickSpread`), a `{low, high}` stays as sent, a missing or half-null value stays nil, and `rough` is the server's flag.
  - (b) Show picks as one number and keep ranges for photos only.
  - (c) A separate search-result type, converted when the item list opens.
- Decision: (a). The per-serving label wins over the dining `serving` text. The panel shows dining halls, USDA (labelled restaurants and generic) and packaged food, hides skipped groups, and says "Could not load" for a failed one.
- Evidence: Packages/StezuCore/Sources/StezuCore/FoodSearch.swift, App/Sources/Food/FoodSearchPanel.swift, FoodSearchClientTests, AppUITests FoodSearchUITests (commit on wt/S-014).
- Reverse if: weighed portions show packaged picks are much tighter than 25%; then give packaged labels their own spread.

## D-066 The fake transport answers a route narrowed by one query pair before the bare route

- Status: proposed by night agent, 2026-10-25 (S-014).
- Problem: search and text estimate share one route (GET /search), but `-uitest` needs a different synthetic reply for each, and FakeVMTransport keyed only by method and path.
- Given: `VMRequest` carries its query as a dictionary; `UITestFixtures.vmRoutes` is a flat route-to-response map shared by every story.
- Constraints:
  - Keying the fake by the full query breaks every fixture whose query holds a date or typed text.
  - A reply that always includes an estimate breaks the contract (the estimate group is "available" until asked).
- Options:
  - (a) A key may add one `name=value` pair ("GET /search?estimate=true"); a request holding that pair gets it, otherwise the bare route answers.
  - (b) Give FakeVMTransport a closure that builds replies.
- Decision: (a), a few lines in `FakeVMTransport.send`.
- Evidence: Packages/StezuCore/Sources/StezuCore/VMTransport.swift, App/Sources/UITestFixtures.swift, FoodSearchClientTests/testTextEstimateIsRough (commit on wt/S-014).
- Reverse if: a fixture needs two pairs at once; then switch to (b).
## D-067 Health sync reads one anchored page at a time and saves it to an on-device queue with its anchor before sending

- Status: proposed by night agent, 2026-10-25 (S-028).
- Problem: every Health type the app reads has to reach POST /sync, first as a 90-day backfill and then only as changes (deletions included), in requests of about 2,000 items, without blocking the UI and without losing anything when there is no server, no network or a 5xx.
- Given: the /sync contract (D-053): samples keyed by HealthKit UUID, deletions kept as tombstones, a replayed `batch_id` is safe, at most 5,000 items per request. `HealthStore` is the only way into HealthKit; `VMTransport` the only way to the server, and it throws `notConfigured` until Settings has a server.
- Constraints:
  - Moving an anchor before its batch is safely stored loses those samples if the app dies or the send fails.
  - Reading the whole backfill into memory and the queue at once makes one very large state file that gets rewritten after every batch.
  - Two passes at once (open, foreground, Finish, Sync now) could both send the head of the queue and then both drop it, which removes a batch that was never sent.
  - Showing a sync time when the server never answered breaks "absent is not zero".
- Options:
  - (a) Per type, read one page of at most 2,000 changes from the stored anchor (`HealthStore.changes`, HKAnchoredObjectQueryDescriptor in the app); append it to `SyncState.pending` as a batch with a new UUID, store the new anchor, save the state (sync-state.json), then send the queue in order. A batch leaves the queue only on a 2xx, and the first failure ends the pass. The `HealthSync` actor runs one pass at a time.
  - (b) Send straight from the query results and move the anchor only after a 2xx; nothing is queued.
  - (c) Read everything first, queue all of it, then send.
- Decision: (a). A batch and its anchor are saved together, so a crash or failure leaves either the old anchor (the page is read again) or the queued batch (resent with the same `batch_id`), never a gap. Since a pass stops at the first failure, the queue holds at most one page while offline. After the queue is empty, GET /sync/status gives `samples_total`; only a 200 there sets `lastSyncAt`. Settings shows "--" until then, and adds "n waiting" while batches are queued. Passes run on open and foreground (scenePhase active) and after Finish, detached at utility priority. `-uitest` syncs only on Sync now.
- Evidence: Packages/StezuCore/Sources/StezuCore/HealthSync.swift, Packages/StezuCore/Sources/StezuCore/HealthStore.swift, App/Sources/Health/HealthKitStore.swift, App/Sources/Settings/HermesSync.swift, HealthSyncTests (commit 531f56a on wt/S-028).
- Reverse if: a 4xx other than 413 shows up in practice (a 400 batch would stay at the head of the queue for good, so it would need to be logged and dropped), or the first backfill takes so long that iOS suspends it often; then send pages from a background task.

## D-068 An edit rescales an item's own ranges by the new servings count, and Log writes the confirmed items as one file beside the meal photos

- Status: proposed by night agent, 2026-10-26 (S-015).
- Problem: before Log the item list changes (replace, half-serving steps, remove, add), the ranges and totals must follow each change without a server call, and the logged meal must be stored on the phone in a way that Undo can take back exactly.
- Given: a matched item carries ranges for `servings` of `serving` (D-049), a search pick is an item at 1 serving (D-065), and captured meals live as files in one folder (`<id>.jpg`, `<id>.json`, `<id>.scan`, D-063).
- Constraints:
  - Recomputing ranges on the server breaks offline editing and costs a call per tap.
  - Keeping a per-serving base and the count separately breaks nothing yet but adds a second item type the sheet and the store would both need.
  - Storing logged meals inside the queue files breaks S-017's rule that nothing in the queue changes a meal's files, and Undo would have to rewrite a file instead of removing one.
- Options:
  - (a) `MatchedItem.withServings(n)` scales both ranges by n / servings (an item without a count is taken as 1); `MealEdit` holds the items and sums totals from them. Log writes `LoggedMeal` (status confirmed, the edited items) as `<id>.log` in the same folder; Undo deletes that file.
  - (b) A per-serving base plus a count per line, a separate logged-meals store.
  - (c) Send the edited list to the server and store what it returns.
- Decision: (a). Steps are 0.5 and clamp at 0.5; a replacement keeps the servings counted for the item it replaces; an unknown range stays nil when scaled. A search pick is logged under the pick's id, a photo under the meal's id.
- Evidence: Packages/StezuCore/Sources/StezuCore/MealEdit.swift, App/Sources/Food/MealCapture.swift, App/Sources/Food/MealEditor.swift, MealEditTests, MealLogStoreTests (commit on wt/S-015).
- Reverse if: logged meals have to sync to the server (/sync) or be edited after Log; then they need their own store with ids the server knows.

## D-069 The week's sessions list is merged by start time: a Health workout within a minute of a Stezu session is that session, and Health workouts are dated by their start

- Status: proposed by night agent, 2026-10-26 (S-023).
- Problem: Data lists this week's sessions from two places, Stezu's own log (seeded history and finished-workouts.json) and Health's workouts, and every session Stezu finishes is also written to Health (D-056), so the same session arrives twice; the Food row needs one weekly figure from meals whose kcal and protein are ranges.
- Given: Finish writes the workout with the session's start and a deterministic external id (D-056); `HealthSample` carries a date, source name and bundle id but no external id or end; logged meals are `LoggedMeal` files (D-068) with per-item ranges where an unknown range is nil.
- Constraints:
  - Matching by bundle id alone breaks a reinstall: the local log is gone and every Stezu workout still in Health would vanish from the week.
  - Reading the external id needs a new field on `HealthSample` and both stores; it also misses the same session recorded by a watch app.
  - Dating workouts by their end (as other samples are) breaks start-time matching, since a session's end is not kept in the seeded history.
  - Summing an unknown item as 0 breaks "absent is not zero".
- Options:
  - (a) Merge on start time: Stezu sessions first (repeats within 1 s count once), then each Health workout unless it starts within 60 s of one already listed; `HealthKitStore` dates workouts by `startDate`.
  - (b) Drop every Health workout from Stezu's bundle.
  - (c) Add the external id to `HealthSample` and match on it.
- Decision: (a). Food: each logged day's total is its meals' lows summed and highs summed; the week is the mean of the lows and the mean of the highs over logged days; a day with an unknown item counts as logged but is left out of that mean, and the confidence reason says so.
- Evidence: Packages/StezuCore/Sources/StezuCore/WeeklyIntake.swift, App/Sources/Health/HealthKitStore.swift, App/Sources/Data/WeeklyFoodWorkoutRows.swift, WeeklyStatTests (commit on wt/S-023).
- Reverse if: two real sessions start within a minute of each other, or Health workouts need their end date on Sources; then match on the external id instead.

## D-070 The Day view tags each record with its owner, and only Stezu-owned records get Delete, each removed where it is stored

- Status: proposed by night agent, 2026-10-26 (S-025).
- Problem: a day mixes Stezu's own records (weigh-ins written to Health, logged meals, finished sessions) with other apps' Health samples, and the Day view must let Isaac change only Stezu's, with each change landing in the store the record came from.
- Given: Stezu weigh-ins live only in Health, as body-mass samples from Stezu's bundle (D-057); logged meals are `<id>.log` files (D-068); finished sessions are entries in finished-workouts.json; a Health workout within 60 s of a Stezu session is that session (D-069); `-uitest` scenarios seed meals and sessions in memory only.
- Constraints:
  - Deciding ownership from the source name alone breaks when another app is also called "Stezu" and lets the view delete samples it did not write.
  - A HealthKit delete by type and date alone would remove other apps' weigh-ins at that instant.
  - Deleting the Health copy of a finished session needs a workout delete in `HealthStore` that no story has asked for yet.
  - Seeded scenario records cannot be deleted from a store, so a reload would bring them back.
- Options:
  - (a) `DayRecord.Owner`: `.weighIn(date)` only for Stezu's bundle id, `.meal(id)`, `.session(start)`, else `.health`. Delete: `HealthStore.deleteBodyMass(at:)` (HealthKit predicate: this app's source and that instant), `MealCaptureStore.unlog`, or rewriting finished-workouts.json without the session; the view also remembers what it deleted this visit. A meal edit rewrites its `.log` with the same id.
  - (b) Show Edit and Delete on every record and let HealthKit refuse other apps' samples.
  - (c) Read-only Day view now, editing later.
- Decision: (a). Deleting a session leaves its Health copy in Health, where it then shows as a read-only Health workout.
- Evidence: Packages/StezuCore/Sources/StezuCore/DayRecords.swift, Packages/StezuCore/Sources/StezuCore/HealthStore.swift, App/Sources/Health/HealthKitStore.swift, App/Sources/Data/DayView.swift, DayRecordsTests (commit on wt/S-025).
- Reverse if: sessions need deleting from Health too (add a workout delete by external id), or records gain stable ids from a shared store.

## D-071 A scanned code is looked up once at a time, decodes like a packaged search pick, and "not found" is its own state

- Status: proposed by night agent, 2026-10-26 (S-016).
- Problem: in Barcode mode the scanner reports codes continuously while the camera points at a package, the reply for a known product must reach the same item list as a search pick, and an unknown code must not look like a product with no values.
- Given: GET /barcode/{gtin} answers `{"status": "found", ...}` with the same product fields as a packaged search result (`per_serving`), or `{"status": "not_found", "gtin": ...}` with HTTP 200; errors are 400 or 502 (server/README.md, server/stezu_server/app.py). A search pick opens the item list at 1 serving with a range around its per-serving value (D-065). The photo camera runs its own AVCaptureSession (S-012).
- Constraints:
  - Looking up every report breaks the screen: the same code would open the list again and again, and replies could arrive out of order.
  - A second decoder for the product fields breaks consistency: a barcode item and the same search item could show different ranges.
  - Mapping "not found" to an empty item breaks absent-is-not-zero (it would show 0 or "--" kcal as if it were a product).
  - Running the photo session and VisionKit's scanner at once breaks on the phone (one camera, two sessions).
- Options:
  - (a) The scanner passes only newly recognized codes (DataScanner's didAdd), the screen drops codes that are not 8 to 14 digits and any code while a lookup or a sheet is open, `BarcodeClient` decodes a found reply with the search result decoder and returns `.found(item)` or `.notFound(gtin)`; any other status or HTTP error throws and shows "Could not look up the code". Barcode mode stops the photo session and Photo mode restarts it.
  - (b) Debounce codes by time and look up the last one.
  - (c) Let the scanner stop after the first code and restart it when the sheet closes.
- Decision: (a). In `-uitest` `BarcodeSource.fixture` delivers one synthetic code 8 seconds after the switch. A found product opens the existing pick sheet (`PickedItem`), so Log works as for a search pick.
- Evidence: Packages/StezuCore/Sources/StezuCore/Barcode.swift, Packages/StezuCore/Sources/StezuCore/FoodSearch.swift, App/Sources/Food/BarcodeScanner.swift, App/Sources/Food/FoodView.swift, BarcodeClientTests, BarcodeUITests (commit on wt/S-016).
- Reverse if: products with no per-serving values are common enough to need a per-100 g or per-package choice, or the scanner has to read several packages for one meal.

## D-072 Log saves the meal on the phone, then writes one food correlation tagged with the meal id, and saves whether Health took it

- Status: proposed by night agent, 2026-10-26 (S-018).
- Problem: a logged meal must reach Apple Health as one food entry from ranges, a denied or failed write must not lose the meal, and Undo must take the entry back out of Health as well as off the phone.
- Given: Log writes `<id>.log` (D-068); meal amounts are low-high ranges (D-049); HealthKit stores single quantities and keeps custom metadata; workouts already record `inHealth` after their write (S-008).
- Constraints:
  - Writing to Health before the local save breaks "saved locally first": a crash between the two leaves a Health entry the phone does not know.
  - Writing the low or the high alone breaks the range rule; the midpoint without the ends loses them for good.
  - Finding the entry again by date or value breaks Undo when two meals share a minute.
- Options:
  - (a) `MealHealth.log`: save the meal, write `FoodEntry` (the totals' midpoints) through `HealthStore.saveFood` as one HKCorrelation of type food holding energy and protein samples, each with its low and high in metadata (`stezu_kcal_low/high`, `stezu_protein_g_low/high`); the meal id is the correlation's sync identifier and `stezu_meal_id` on all three objects; then save the meal again with `inHealth` true or false. Undo deletes the three by `stezu_meal_id`.
  - (b) Two loose samples (energy, protein) with no correlation.
  - (c) Write Health first and save only on success.
- Decision: (a). The sync version is the write time in ms, so a later write of the same meal replaces the entry. A meal with neither total known writes nothing and is "Not in Health". A failed local save throws before Health.
- Evidence: Packages/StezuCore/Sources/StezuCore/MealHealth.swift, Packages/StezuCore/Sources/StezuCore/HealthStore.swift, App/Sources/Health/HealthKitStore.swift, App/Sources/Food/FoodView.swift, MealHealthTests (commit on wt/S-018).
- Reverse if: HealthKit rejects custom-key deletes on a correlation type on a device, or meals become editable after Log (S-019); then delete by the correlation's own objects and rewrite with a new sync version.

## D-073 History reads meals from the meal files, and an edit or delete goes to the phone first, then replaces or removes the Health entry by meal id

- Status: proposed by night agent, 2026-10-26 (S-019).
- Problem: the camera's strip and History must show today's and past meals as summed ranges, and an edit or a delete of a past meal must change the phone's copy, the totals and the meal's Health entry together, with no copy left behind.
- Given: each logged meal is `<id>.log` in the meal folder and pending photos are `<id>.json` without a `.scan` (D-068, S-017); a meal's Health entry is a food correlation tagged with the meal id (D-072); a scenario's seeded meals so far lived only in `AppEnvironment.mealHistory`, in memory.
- Constraints:
  - Keeping seeded meals outside the store breaks edit and delete: a deleted seed comes back on the next read, and the strip and History disagree.
  - Relying on HealthKit's sync-version replace alone breaks "replaced" if the samples inside the old correlation survive; two entries would double the day in Health.
  - Deleting from Health first breaks "never lose data" when the phone's write then fails.
- Options:
  - (a) `MealCaptureStore.days()` gathers `.log` meals and pending photos into `FoodDay`s (newest first, totals from `FoodRange.total`, nil with no meal). Save: `MealHealth.replace` writes the edited `.log` (same id and time), deletes the Health entry by meal id, then writes it again as Log does. Delete: `MealHealth.delete` removes the `.log`, then the Health entry. `-uitest-scenario food-history` writes its meals into the memory store at launch, and the fixture photo when Food opens.
  - (b) Keep an in-memory list in the view and write back on dismiss.
  - (c) Mark deleted meals with a tombstone file and filter on read.
- Decision: (a). Every reader (strip, History, Data) sees the same files, so an edit or delete shows everywhere on the next read. A failed Health delete leaves the meal deleted on the phone; the result is returned, not shown.
- Evidence: Packages/StezuCore/Sources/StezuCore/FoodDay.swift, Packages/StezuCore/Sources/StezuCore/MealHealth.swift, App/Sources/Food/MealCapture.swift, App/Sources/Food/FoodHistory.swift, App/Sources/Food/FoodView.swift, FoodDayTests, MealHistoryUITests (commit on wt/S-019).
- Reverse if: S-029 needs tombstones for /sync (then (c) on top of (a)), or HealthKit's sync-version replace is shown on a device to remove the old samples, so the delete before the rewrite can go.

## D-074 Home reads each card's numbers from the same stores as its area, every time Home appears

- Status: proposed by night agent, 2026-10-26 (S-026).
- Problem: the Home cards must show, with 0 taps, the numbers Data, Food and Workout record (trend weight and weigh-in days, today's food ranges and meal count, this week's sessions and the next template), agree with those areas, and show "--" for anything not recorded. They showed only "--", and their model still carried the target, protein-floor and last-top-set inputs D-032 took out of v1.
- Given: Data's Weight row reads `WeeklyWeight.load` from Health (D-057); Data's Workouts row merges seeded and finished Stezu sessions with Health workouts through `WeeklyIntake.workouts` (S-023); today's food is `FoodDay.on(now)` over the meal files (D-073) plus a scenario's `mealHistory`; Workout offers `TemplateLibrary.next(after: nil)`; AppShell rebuilds HomeView each time an area closes.
- Constraints:
  - A separate Home cache or summary file breaks agreement: it goes stale after a weigh-in, a Log or a Finish until something rewrites it.
  - Counting only finished Stezu sessions (Workout's own row) breaks agreement with Data, which also counts Health workouts.
  - Keeping the target fields in `HomeInputs` breaks D-032 (no target anywhere); dropping them changes two existing HomeViewModelTests, which were rewritten to the new inputs with the same checks (order, labels, values, confidence, "--").
- Options:
  - (a) `HomeInputs.load(from: AppEnvironment)` runs in HomeView's `.task` on every appear and reads the same calls the areas make: `WeekWeight`, `FoodDay`, `[WeekWorkout]` and the next template's name. `HomeViewModel` stays pure and formats them; a nil or empty input is "--" with a nil confidence.
  - (b) Each area writes a small summary to the store when it changes, and Home reads the summaries.
  - (c) One shared observable model the areas mutate.
- Decision: (a). The workout card's confidence is high, with "n from Stezu, m from Health" as its reason. A failed Health read is absent. New scenario `home-week` is data-food-week plus two meals today.
- Evidence: App/Sources/HomeViewModel.swift, App/Sources/HomeView.swift, App/Sources/UITestFixtures.swift, App/Tests/HomeViewModelTests.swift, App/UITests/HomeCardsUITests.swift (commit on wt/S-026).
- Reverse if: the reads make Home visibly slow to fill on a device (then (b)), or the target loop returns after D-032 is reversed.

## D-075 A meal change is queued as a `/sync` record batch in the Health sync queue, saved before the screen goes on, and sent by the next pass

- Status: proposed by night agent, 2026-10-26 (S-029).
- Problem: every logged, edited, undone or deleted meal must reach the server's records, survive being offline or a relaunch, never block the screen, and keep a deleted meal deleted on the server even though the phone keeps no tombstone file.
- Given: `HealthSync` keeps a persisted queue of `SyncBatch`es (sync-state.json, D-067) that leave only on a 2xx and are resent with the same `batch_id`; the server keys records by `(kind, id)` and keeps only a newer `updated_at` (server/README.md); meal changes happen in FoodView (Log, Undo), FoodHistory (save, delete) and DayView (save, delete) (D-073).
- Constraints:
  - A second queue for records breaks "the same queue and retry" and lets records and samples race.
  - Sending straight from the view breaks offline: a failed send would be lost, and the screen would wait on the network.
  - A timestamp at seconds resolution breaks edits made within a second of Log: the server counts them as duplicates.
- Options:
  - (a) `SyncRecord.meal`/`.deletedMeal` build one record (`MealRecord` payload: id, eaten_at, day, status, edited, in_health, items with item_id, source, halls, serving, servings, confidence, rough, kcal and protein_g ranges; no photo). `AppEnvironment.syncMeal` awaits `HealthSync.enqueue` (a records-only batch appended and saved), then starts a detached pass. `run` flushes again before GET /sync/status so a record queued mid-run goes too, and reads `records_total` for the Settings row.
  - (b) Keep a separate records outbox file and its own retry.
  - (c) Rebuild all meals from the meal files on every pass and diff against what was sent.
- Decision: (a). `updated_at` carries milliseconds. `SyncBatch.records` is optional, so a queue saved by S-028 still loads. The `-uitest` fake counts the live records it has received in its GET /sync/status answer (`FakeVMTransport(countsRecords:)`), and a meal change starts a pass under `-uitest` too.
- Evidence: Packages/StezuCore/Sources/StezuCore/SyncRecord.swift, Packages/StezuCore/Sources/StezuCore/HealthSync.swift, Packages/StezuCore/Sources/StezuCore/VMTransport.swift, App/Sources/Settings/HermesSync.swift, App/Sources/Food/FoodView.swift, App/Sources/Food/FoodHistory.swift, App/Sources/Data/DayView.swift, HealthSyncTests/testMealRecordCarriesRangesAndSource, HermesSyncUITests/testLoggedMealIsSynced (commit on wt/S-029).
- Reverse if: the queue grows big enough that one batch per meal change crowds the 5,000-item limit's spirit (then coalesce pending records by id), or the server starts rejecting records without a payload key.

## D-076 Data the app records is stored on the phone first, then sent to the server; Apple Health is a copy

- Status: decided by Isaac, 2026-10-26.
- What: workout sets, finished sessions, weigh-ins and meals are saved in the app's own store first, and sent to the VM server as /sync records from there. Writing them to Apple Health stays, as a local copy written after the app's own save, never as the path the data takes to Hermes.
- Why: these records are entered in the app itself, so the app is their source of truth. Routing them through Health loses detail (sets, reps and exercise names don't fit a Health workout) and makes the VM depend on a Health write that can be denied.
- Changes: D-057 (weigh-ins live only in Health) is reversed by S-031. S-030 sends sets and sessions. Meals already work this way (D-068, D-075).
- Reverse if: never for app-entered data. Health remains the source only for what other devices record (the strap and the phone's sensors).

## D-077 The signing team lives in a gitignored Config/Local.xcconfig, included by a committed Config/Signing.xcconfig

- Status: decided by Isaac, 2026-10-26 (infra/local-signing).
- Problem: every `xcodegen generate` rewrote the project without the team Isaac picked in Xcode, so the next device build failed with "StezuHealth requires a provisioning profile with the HealthKit feature" until he picked the team again on StezuHealth and RestActivity.
- Given: the .xcodeproj is generated and gitignored; the repo is public (D-034) and G3 rejects a team, identity or profile in project.yml; CI builds unsigned with CODE_SIGNING_ALLOWED=NO.
- Constraints:
  - A team in project.yml breaks D-034 and G3.
  - A required include of a file that only exists on Isaac's Mac breaks CI and every fresh clone.
- Options:
  - (a) project.yml `configFiles` (Debug, Release) for StezuHealth and RestActivity point at Config/Signing.xcconfig: `CODE_SIGN_STYLE = Automatic` plus `#include? "Local.xcconfig"`. scripts/set-team.sh writes Local.xcconfig with `DEVELOPMENT_TEAM`, taken from its argument or from the OU of the first Apple Development certificate, and runs xcodegen.
  - (b) An environment variable read by XcodeGen (`${DEVELOPMENT_TEAM}` in project.yml): it must be exported in every shell that runs xcodegen, and an unset one writes an empty team.
  - (c) Keep picking the team in Xcode after each generate.
- Decision: (a). The include is optional, so CI and a fresh clone build without a team; Local.xcconfig is in .gitignore.
- Evidence: Config/Signing.xcconfig, scripts/set-team.sh, project.yml, .gitignore, README.md "Build on your Mac" (commit on infra/local-signing).
- Reverse if: the project moves to a paid team shared by several people (then the team may go in a committed xcconfig), or XcodeGen gains a supported local-override file.

## D-078 The app also collects phone-only background data: location, Screen Time, background health sync

- Status: decided by Isaac, 2026-10-26. The mechanisms are proposed.
- What: data that only the iPhone can see is collected by this app and sent to the server like everything else, local first (D-076). That covers location, Screen Time, and Health data synced without opening the app.
- Feasibility on the current free Apple account (Apple's capability table, checked 2026-10-26):
  - Location: works. It needs Info.plist strings and the location background mode. Visits plus significant changes, no continuous GPS (S-032).
  - Background sync: works through a BGAppRefreshTask (S-033). Whether HealthKit background delivery signs on a free account is unverified, so it is left out until checked.
  - Screen Time: Family Controls (development) is available only with the paid Apple Developer Program. Even then, iOS never lets an app read raw usage: a DeviceActivityReport extension can only display it, and a DeviceActivityMonitor extension only receives threshold callbacks for apps the user picked, which are opaque tokens. The routes are under research before any story is written.
- Tension (D-012): passive collection has no logging burden, which is why it is acceptable, but no loop consumes location or Screen Time yet. Each stream stays tracking-only until a loop names what it is for.
- Privacy: location and usage data never enter the repo, logs or prompts. They live in the VM's health database (mode 0600).

## D-079 Background location and background sync keys go in project.yml: strings as INFOPLIST_KEY_ settings, arrays in an `info:` block

- Status: proposed (infra/background-location), 2026-10-26.
- Problem: S-032 (location) and S-033 (background sync) need Info.plist keys and background modes, which a card may not add (AGENTS.md rule 7), and the app target has no Info.plist file: it uses GENERATE_INFOPLIST_FILE, whose `INFOPLIST_KEY_` settings cover the usage strings but not the array keys UIBackgroundModes and BGTaskSchedulerPermittedIdentifiers.
- Given: D-078 (phone-only background data, decided); the .xcodeproj is generated by XcodeGen and gitignored; RestActivity already combines INFOPLIST_FILE with GENERATE_INFOPLIST_FILE; CI builds unsigned.
- Constraints:
  - A hand-written, committed Info.plist next to project.yml splits the keys over two files, which can drift apart.
  - An App/Info.plist under a source path (App/Sources, App/Shared) would be copied as a resource and break the build ("multiple commands produce Info.plist").
  - XcodeGen's generated plist defaults CFBundleShortVersionString to "1.0", which would hide MARKETING_VERSION.
  - The HealthKit background-delivery entitlement may not sign on the free team (D-078); adding it could break device builds.
- Options:
  - (a) project.yml: the two location strings as `INFOPLIST_KEY_` settings like the existing usage strings; UIBackgroundModes (location, fetch, processing) and BGTaskSchedulerPermittedIdentifiers (`com.ik301.stezuhealth.sync`) in the target's `info:` block, which xcodegen writes to the gitignored App/Info.plist and sets as INFOPLIST_FILE; Xcode merges the generated keys into it. The block also sets the versions to $(MARKETING_VERSION) and $(CURRENT_PROJECT_VERSION).
  - (b) A committed App/Info.plist with the arrays, referenced through INFOPLIST_FILE, as RestActivity does.
  - (c) Turn off GENERATE_INFOPLIST_FILE and keep every key in an `info:` block.
- Decision: (a). project.yml stays the one place for keys, and the existing settings keep working unchanged. A step in the ios CI job reads the built app's Info.plist and fails if the location strings, the three background modes or the task identifier are missing, or if the version fell back to 1.0. No HealthKit background-delivery entitlement; S-033 uses BGAppRefreshTask only.
- Evidence: project.yml, .gitignore, .github/workflows/ci.yml ("Check the built app's Info.plist"), AGENTS.md (commit on infra/background-location).
- Reverse if: XcodeGen or Xcode stops merging an `info:` plist with the generated keys, or the app gains enough array keys that (c) is simpler. Add background delivery only after it is confirmed to sign on the team in use.

## D-080 Sets and sessions become `/sync` records with ids derived from their times, queued after the phone's save, and stored workouts are backfilled once behind a flag in the sync state

- Status: proposed by night agent, 2026-10-26 (S-030).
- Problem: every logged and undone set and every finished session must reach the server's records with ids that stay the same across an undo, a backfill and a replay, the phone's own save must come before both the record and the Health copy, and the workouts stored before this build must be sent once, never twice.
- Given: `WorkoutSet` has no id; a session's Health external id is `stezu.workout.<start ms>` (D-056); the logger is saved to active-workout.json after each change (D-045) and finished sessions to finished-workouts.json; meal records already ride `HealthSync.enqueue` (D-075); sessions store exercise names only, while templates and the library (swaps, custom exercises) hold the keys.
- Constraints:
  - Adding a stored id to `WorkoutSet` breaks every saved logger and finished file (they would decode with fresh random ids, so a backfill would not match what was sent).
  - Writing to Health before the phone's save (the old `WorkoutFinish.finish` order) breaks D-076: a slow or denied Health write would hold up the session and its record.
  - A pass already running when the last record is queued would leave that record waiting until the next launch, since `run` refused a second pass.
- Options:
  - (a) Set id `<session id>.set.<logged-at ms>`, session id = the Health external id. `SyncRecord.set/.deletedSet/.session` build `SetRecord` and `SessionRecord` payloads under the one `payload` key (decoded by kind), with the field names of server/README.md (`exercise_name`, `started_at`, `ended_at`, `exercises[].exercise_key`). Log and Undo save the logger, then `syncRecords`; Finish `close`s the session, saves finished-workouts.json, queues the record, then writes Health and saves `inHealth`. `SyncState.workoutsBackfilled` gates `HealthSync.backfillWorkouts`, run from the launch/foreground hook. `run` asked for while running sets a flag, and the running pass goes once more.
  - (b) Store a UUID per set and migrate the old files on first launch.
  - (c) Rebuild all sets and sessions from the files on every pass and send them all.
- Decision: (a). Exercise keys come from the library first and the templates second (templates win on a shared name); an unknown name sends a null key. `pounds` is always present, null for bodyweight.
- Evidence: Packages/StezuCore/Sources/StezuCore/WorkoutRecord.swift, SyncRecord.swift, HealthSync.swift, WorkoutFinish.swift, App/Sources/Settings/HermesSync.swift, App/Sources/Workout/WorkoutLoggerView.swift, App/Sources/Workout/WorkoutView.swift, WorkoutRecordTests (3), HermesSyncUITests/testLoggedSetsAndFinishedWorkoutAreSynced (commit on wt/S-030).
- Reverse if: two sets can be logged in the same millisecond of one session (then store an id per set), or the server starts treating an equal record replayed by the backfill as a conflict.

## D-081 iPhone Screen Time reaches the server through the Mac: a daily launchd job reads Biome App.InFocus and posts `app_usage` records

- Status: proposed (infra/mac-screentime-uploader, daytime session), 2026-10-26.
- Problem: D-078 wants the iPhone's per-app Screen Time on the server, but on the free Apple account no app code can read it: Family Controls needs the paid program, and before iOS 26.4 iOS never exports usage numbers at all (research note 11).
- Given: Isaac's MacBook has Share Across Devices on and holds the iPhone's App.InFocus events in Biome (remote streams, SEGB files, device list in sync.db); the Mac is always on the tailnet and reaches the server at the app's base URL with a device token; POST /sync stores records by (kind, id) with the newest updated_at winning; ActivityWatch already covers the Mac itself; Biome keeps about four weeks.
- Constraints:
  - Biome is private and undocumented; its format changed in 2025, so a parser can break with a macOS update.
  - Reading it needs Full Disk Access for the binary that opens the files; a launchd job through /usr/bin/python3 (a shim) gets no grant of its own, and the grant breaks when the interpreter path moves.
  - The iPhone's events reach the Mac late and out of order, so a strict "last event uploaded" cursor skips data; a run before midnight sees apps still in focus.
  - The repo is public (D-034): no device ids, names, usage or server URLs in code, tests or PRs.
  - No new dependencies on the Mac beyond the Command Line Tools python.
- Options:
  - (a) A stdlib Python script with its own SEGB and protobuf reader, run daily at 20:00 by a launchd agent that starts the real interpreter binary (the one granted Full Disk Access); it re-sends the trailing 7 days every run and holds back intervals still open.
  - (b) Install nichtlegacy/screentime or aw-import-screentime on the Mac and forward from its database or ActivityWatch buckets.
  - (c) Pay for the Apple Developer Program and use iOS 26.4's DeviceActivityData export in the app.
- Decision: (a). It is free, adds no dependency, and posts the same record contract the app uses. Default devices are only remote peers whose sync.db model is an iPhone; otherwise the run sends nothing and asks for STEZU_DEVICES. Intervals end at focus loss or the next app's focus gain, drop at zero length, and are capped at 4 hours (marked capped). The record id hashes device, bundle id and start, and updated_at is the run's time, so a re-send or a corrected end replaces the row. The state file only records the last run and its counts, plus how far back the window reaches after a gap. Server views stezu_app_usage and screen_time_daily read the records (server PR).
- Evidence: mac/screentime/ (stezu_screentime.py, install.sh, uninstall.sh, com.ik301.stezu.screentime.plist, README.md, Tests/), scripts/gate-linux.sh G6. Tested on Linux with synthetic SEGB v1/v2 files and a synthetic sync.db only; not yet run on a Mac (macOS 26.6.2 layout assumed from 26.1 and 27 reports).
- Reverse if: a macOS update changes the Biome layout beyond a parser fix, Share Across Devices stops carrying iPhone events, or the paid program is bought and the in-app export (c) gives Apple's own totals.

## D-082 Weigh-ins live in weigh-ins.json behind an actor; the weight screens read them through a HealthStore wrapper, and Health's earlier Stezu weigh-ins are imported once

- Status: proposed by night agent, 2026-10-26 (S-031).
- Problem: a weigh-in must survive a denied or failed Health write and still reach the server, the weight row, the 8-week detail, Home and the Day view must all show the phone's weigh-ins instead of Health's, and the weigh-ins earlier builds wrote only to Health (D-057) must move to the phone without being counted twice.
- Given: D-076 (the phone first, Health a copy, decided); `WeeklyWeight.load`, `MetricHistory.load` and `DayRecords.load` all read body mass through `HealthStore.samples(of: .bodyMass)` and keep only Stezu's bundle id (D-047); records ride `HealthSync.enqueue` (D-075); Health only becomes readable after the Connect sheet (S-020).
- Constraints:
  - Rewriting the three loaders to take weigh-ins breaks the card's file budget and their existing tests' signatures.
  - Importing before Health has asked reads nothing, and a once-only flag set then would never import.
  - Matching imports by time breaks on two weigh-ins in the same second; a Health UUID or the weigh-in id in metadata does not.
- Options:
  - (a) `WeighInStore` (actor over `WeighInLog`: weigh-ins and a `migrated` flag, saved to weigh-ins.json after every change). Add saves, then writes Health with `stezu_weighin_id` metadata and saves `inHealth`, then queues a `weigh_in` record (id, measured_at, pounds, in_health). Delete removes locally, deletes in Health by metadata id or UUID, then queues a tombstone. `WeighInHealth` wraps the HealthStore: its body-mass read imports once (only after Connect), drops Health's Stezu samples and adds the store's as Stezu samples; every other call passes through. The four screens read `AppEnvironment.weightHealth`.
  - (b) Add a weigh-ins parameter to each loader and merge in every view.
  - (c) Keep Health as the store and copy each new sample to the server from the anchored sync.
- Decision: (a). `HealthSample.id` carries the metadata id, else Health's UUID, so a re-import matches either; a fake sample with no id gets `health.<ms>`. An import with nothing found queues nothing and starts no pass.
- Evidence: Packages/StezuCore/Sources/StezuCore/WeighInStore.swift, HealthStore.swift, HealthSources.swift, SyncRecord.swift, App/Sources/Data/WeightRow.swift (WeighInFile, AppEnvironment.weightHealth), App/Sources/Health/HealthKitStore.swift, App/Sources/Data/DayView.swift, WeighInStoreTests (3), HermesSyncUITests/testWeighInIsStoredLocallyAndSynced (commit on wt/S-031).
- Reverse if: another screen starts reading body mass for weigh-ins without the wrapper (then pass weigh-ins explicitly), or Health's own writes from other Stezu installs need merging (then import on every read, matched by id).

## D-083 Importing a program file replaces the whole program; history is kept

- Status: decided 2026-10-26. Isaac switched from the five-day split to Push and Pull. The mechanism is proposed (S-034).
- What: a program file is the whole program. After a confirmation, the template list becomes exactly the file's templates, in its order. Removed templates disappear from the list, never from history. Once a program has been imported, the bundled seed stops upserting, so removed templates can't come back.
- Why: under D-052 an import only added or replaced templates by key, so switching programs would leave the old days in the list beside the new ones, with no way to remove them in the app.
- Reverses: D-052's upsert-only import, under its own Reverse-if.
- Reverse if: Isaac wants to keep several programs side by side. Then programs become named sets, not a single list.

## D-084 Optional blocks (Abs) are add-on templates appended to the current workout, not separate workouts

- Status: decided 2026-10-26. Isaac wants an optional abs section that can follow any day. The mechanism is proposed (S-035).
- What: a program file can mark a template `"addOn": true`. While a workout is running, the logger shows "+ <name>". Tapping it appends that template's exercises to the same workout.
- Options considered:
  - (a) Add-on templates appended in-session: chosen.
  - (b) Abs as its own workout. It costs a second Start and Finish, and makes two Health workouts for one gym visit.
  - (c) An "optional" flag on exercises inside each day. The same exercises would be copied into every day, and a change would have to be made in several places.
- Why (a): one tap, one session, and the block is defined once.
- Reverse if: add-ons need to run on their own (a home abs day). Then also allow starting an add-on as a workout.

## D-085 A replace is checked, confirmed, then written as one library value with a seed-stop flag and the removed templates' names

- Status: proposed by night agent, 2026-10-26 (S-034).
- Problem: under D-083 an import removes templates, but past sessions name themselves only by template key, a newer bundled seed would add the removed days back at the next launch, and older library files must still load.
- Given: D-042 (one workout-templates.json holding `TemplateLibrary`; the seed upserts at launch when its version is newer). D-046 (sessions carry `templateKey`; the logger keeps its own copy of the template). D-052 (`ProgramImport.parse` checks the whole file first). History and the S-030 sync queue live in other files. History rows looked names up in the current templates, else showed "Workout".
- Constraints:
  - Storing the template name in each session breaks sessions saved before this card, which have none, and changes the finished-workout and sync formats.
  - Bumping or clearing `seedVersion` to stop the seed breaks "an import is not a seed" and is undone by the next seed with a higher version.
  - Synthesized decoding of a new non-optional field breaks every library file saved before this card (keyNotFound).
  - Applying the file before Cancel can be chosen breaks "Cancel changes nothing".
- Options:
  - (a) The library gains `programImported` and `removedNames` (key to name), both read with `decodeIfPresent`; `replaceProgram(with:)` records the names of templates the file lacks, sets the templates to the file's in order, adds the file's keys to `editedKeys` and sets the flag; `upsert` returns false while the flag is set; History reads `names` (current templates over removed ones).
  - (b) Names in each `WorkoutSession` and a seed opt-out in UserDefaults.
  - (c) Keep removed templates in the library with a hidden flag.
- Decision: (a). The screen checks the picked file with `WorkoutTemplateStore.check` (no change), holds the templates in `pending` and shows an alert naming them; Replace applies and saves the library, Cancel drops `pending`. A refused file shows its message without the alert. Nothing is queued for the server and no session or sync file is written.
- Evidence: Packages/StezuCore/Sources/StezuCore/WorkoutTemplate.swift, ProgramImport.swift, App/Sources/Workout/ProgramFilePicker.swift, App/Sources/Workout/WorkoutView.swift, Packages/StezuCore/Tests/StezuCoreTests/ProgramImportTests.swift (1fbff75).
- Reverse if: programs become named sets (D-083's Reverse-if), or a template is renamed often enough that history should show the name it had at the time.

## D-086 Appended add-ons live in the logger as extra slots after the day's, saved with it, with last numbers from any template

- Status: proposed by night agent, 2026-10-26 (S-035).
- Problem: under D-084 an add-on's exercises join a workout already running, and they must log, undo, swap, rest, survive a relaunch and finish as one session under the day's key, while add-ons follow different days and the logger's saved file predates them.
- Given: D-046 (sessions carry `templateKey`; last numbers prefer the same template, by exercise name). D-055 (`SetLogger` is saved whole as active-workout.json after every change and resumed from it). D-083 (an import replaces the library's templates). Logging, undo and swap address exercises by slot index; the S-030 records take exercise keys from the templates by name.
- Constraints:
  - Changing `SetLogger.template` to a merged template breaks the session's day key and the resume card's name.
  - A second session for the add-on breaks "one Finish, one Health workout, one workout_session".
  - A new non-optional stored field breaks decoding of a logger saved before this card (keyNotFound), which loses the workout in progress.
  - Same-template lookups for add-on exercises break their last numbers, since the add-on never appears as a session's template.
- Options:
  - (a) `WorkoutTemplate.addOn` (decodeIfPresent, default false); `TemplateLibrary.days` (rotation and list) and `addOns`. The logger stores appended add-on templates in an optional field; its slots are the day's exercises then each add-on's, and every slot lookup reads them, so log, undo, swap and rest work unchanged. `append` looks up each new exercise's last numbers with `WorkoutHistory.lastSession` (any template) unless the day already has that exercise, and moves the card to the first appended slot only when the card's exercise has all its sets.
  - (b) Merge the add-on into a copy of the day's template inside the logger.
  - (c) A second logger for the add-on, merged into one session at Finish.
- Decision: (a). Sessions still hold exercises by name and only logged ones, so an unlogged appended exercise is never saved, and the session record finds add-on keys because `workoutNames` reads every library template.
- Evidence: Packages/StezuCore/Sources/StezuCore/SetLogger.swift, WorkoutTemplate.swift; App/Sources/Workout/WorkoutLoggerView.swift; SetLoggerTests/testAppendAddOnKeepsOneSessionAndSkipsUnloggedExercises (commit on wt/S-035).
- Reverse if: the logger gains free navigation between exercises; then the card need not wait for the day's current exercise before moving into the add-on.

## D-087 Each location event is saved to location-log.json first, then queued as a `visit` or `location` record whose id comes from its time, and sent by one pass of the existing queue

- Status: proposed by night agent, 2026-10-26 (S-032).
- Problem: visits and significant location changes arrive while the app is in the background or was just relaunched for them, often with the phone locked and only seconds of run time. Each one must be kept on the phone before anything else, reach the server once, and a visit reported first on arrival and again on departure must stay one visit.
- Given: CLVisit has no identifier, and its arrival date is the same in both reports; an unknown end is `distantPast` or `distantFuture`; the sync queue in sync-state.json resends batches until a 2xx (D-067, D-075); the server keeps the newest `updated_at` per `(kind, id)` and reads a missing payload field as NULL (server/README.md).
- Constraints:
  - Keeping the events only in the sync queue would lose them as soon as a batch is accepted, so Data's Places row and Sources' last time could not be shown.
  - A random id per event would turn the departure into a second visit, on the phone and on the server.
  - Starting monitoring before the delivery closure is set would drop an event that arrives during a relaunch.
- Options:
  - (a) `LocationRecorder` (an actor) applies the event to `LocationLog`, saves location-log.json, then `HealthSync.enqueue`s one record; then the app runs one `syncHermes` pass, which sends the queue before reading Health. Ids are `visit.<arrival ms>` (departure if no arrival) and `location.<time ms>`; a later event with the same id replaces the stored one and is sent with a newer `updated_at`. Unknown ends and speeds are nil and left out of the payload. Monitoring starts only from `start`, after the closure is set.
  - (b) Write location records straight to the queue and keep no local log.
  - (c) Keep the log in sync-state.json next to the queue.
- Decision: (a). No `beginBackgroundTask`: the pass runs in the time iOS gives a location wake, and anything not sent stays queued for the next pass.
- Evidence: Packages/StezuCore/Sources/StezuCore/LocationRecord.swift, SyncRecord.swift, App/Sources/Data/LocationService.swift, SourcesView.swift, PlacesRow.swift, LocationRecordTests (3), AppUITests LocationUITests/testVisitsAppearAndSync (commit on wt/S-032).
- Reverse if: the server starts needing the explicit `null` keys, a visit's arrival date changes between its two reports (then match an open visit by place), or background passes are cut off before the queue is sent (then add a background task assertion).

## D-088 A background pass is the foreground pass run from a BGAppRefreshTask, cancelled at 25 s or on expiration, and it skips Health while the phone is locked

- Status: proposed by night agent, 2026-10-26 (S-033).
- Problem: on days the app is never opened, Health changes and queued records (meals, visits, weigh-ins) must still reach the server. iOS gives an app refresh about 30 seconds, may end it at any point, and refuses Health reads while the phone is locked. An interrupted run must lose nothing and must not show as a sync.
- Given: `HealthSync.run` already queues each page and saves it together with its new anchor before sending, and a batch leaves the queue only on a 2xx (D-067); BGTaskSchedulerPermittedIdentifiers lists `com.ik301.stezuhealth.sync` (D-078, D-079); HealthKit throws while the phone is locked.
- Constraints:
  - A second, background-only engine would need its own anchors and queue and could send a page twice or skip one.
  - Ignoring the expiration handler gets the app's background time cut by iOS.
  - Sharing `lastSyncAt` would make a background pass look like a foreground one, and Settings could not show either.
- Options:
  - (a) Register one handler at launch. It runs `syncHermes(background: true)` in a detached task; the expiration handler and a 25 s timer cancel that task. `run` checks `Task.isCancelled` before each page read, before each batch send and before GET /sync/status, so it stops between steps with the queue and anchors as last saved. `UIApplication.isProtectedDataAvailable` false means Health is passed as nil, so a locked run sends only the queue. A completed background pass sets `lastBackgroundSyncAt`, not `lastSyncAt`. Every pass, foreground or background, submits the next request (earliest in 1 hour), as does launch.
  - (b) A separate background engine with its own state file.
  - (c) HealthKit background delivery (`enableBackgroundDelivery`) instead of app refresh.
- Decision: (a). (c) needs an entitlement that may not sign on a free account (D-078).
- Evidence: Packages/StezuCore/Sources/StezuCore/HealthSync.swift, App/Sources/Settings/BackgroundSync.swift, HermesSync.swift, SettingsView.swift, BackgroundSyncTests (2), AppUITests HermesSyncUITests/testBackgroundSyncUpdatesStatus (commit on wt/S-033).
- Reverse if: iOS runs the task so rarely that data waits for days (then try background delivery once its signing is checked), or a cancelled send turns out to have reached the server and duplicates show up (batch ids already make a resend idempotent).

## D-089 Next workout is the day after the last one finished, by order, never by date

- Status: decided by Isaac, 2026-10-26 (after a trial Day 1 left Next on Day 1). The mechanism is proposed (S-036).
- What: Next is the day after the template of the most recently finished Stezu session, including an off-schedule one. With none, the first day. Rotation is by order. It ignores dates and weekdays, so a missed day doesn't skip anything.
- Bug fixed: Home and Workout called `next(after: nil)`, which always returns the first day.
- Reverse if: Isaac wants a weekday schedule (Push on Mondays).

## D-090 A finished session can be continued for 12 hours; the same session is replaced, not duplicated

- Status: decided by Isaac, 2026-10-26 ("manually resume an old session"). The mechanism is proposed (S-036).
- What: Continue reopens a finished session that started under 12 hours ago. Finish keeps its id, replaces its Health workout (delete by session id, then save), and re-sends its record with a newer updated_at.
- Why 12 hours: it covers "I hit Finish too early" and coming back later the same day. Continuing an older session would stretch one workout across days in Health.
- Reverse if: he wants to append to older sessions. Then a continuation becomes its own session linked to the first.

## D-091 Home's Data card shows last night's sleep, not weight

- Status: decided by Isaac, 2026-10-26 (S-037).
- What: the number is time asleep for the night that ended this morning, with in-bed time below it. No score (D-032). Weight stays on the Data screen.
- Why: sleep changes every day and is recorded passively by the strap. Weight is entered at the gym, a few times a week.

## D-092 Every sheet uses one header: large title left, plain Done right

- Status: decided 2026-10-26 after Isaac said the Done button was "very off" (S-038).
- What: one SheetHeader view, and no toolbar items in sheets. iOS 26 draws toolbar buttons as floating glass pills, which is where the shadowed Done in Workout History came from.

## D-093 Data rows show a 7-day sparkline; Blood oxygen and Temperature leave the UI

- Status: decided by Isaac, 2026-10-26, after the clickable mock (S-039).
- What: each metric row gets a small week series (bars for counts and sleep, lines for rates), with gaps for missing days. Blood oxygen and Temperature rows are removed. Their Health data is still read and synced if it ever appears.
- Why: he compared sparklines on and off in the mock and kept them. Neither the oxygen row nor the temperature row has received a sample from his phone.
- Reverse if: the rows read as busy on the phone. Then keep the sparkline only on Sleep.

## D-094 Sleep gets its own screen: the sleep window over 7/14/30 nights first, then stages and overnight heart

- Status: decided by Isaac, 2026-10-26 ("i like this UI"). The mechanism is proposed (S-040).
- What: a pushed Sleep screen with last night's numbers, a hypnogram, a one-line overnight heart and breathing range, a 7/14/30 sleep window chart with median bedtime and wake lines, and per-night heart and breathing range bars. Tapping a night selects it.
- Why: the window chart shows duration, timing and consistency in one picture. On his data, bedtime is steady and wake time is scattered, which an average hides. "Usual" is a median, stated as a description, never a target (D-032).

## D-095 The Day view gains a 24-hour timeline across sleep, food, workouts, places and steps

- Status: decided by Isaac, 2026-10-26, from the mock. The mechanism is proposed (S-041).
- What: a timeline above the existing list. It shows recorded data only, with no placeholders.
- Why: it is the one view that connects the domains, which Apple Health cannot show.
- Reverse if: it stays mostly empty once meals and places are logging.

## D-096 The Ingest design system v2 is the visual source of truth

- Status: decided by Isaac, 2026-10-26 (he supplied the design system). Building it is planned below.
- What: `design/system/` holds the tokens (Light and Dark), type scale, spacing, 23 components and clickable walkthroughs for every area. DESIGN.md now points to it.
- Changes from v1:
  - Dark mode follows the phone.
  - Type scales with Dynamic Type.
  - Labels move from #8A8A8A (3.0:1, fails AA) to `muted`.
  - Colour is allowed, but only for data marks: energy, protein, heart and sleep stages. Chrome stays grayscale.
  - Whole rows are buttons.
  - Charts use Swift Charts, a system framework.
- Order: tokens first (an infra PR, because it touches every view), so every new screen is built on them. Then the shared TopBar and chart components, then the four areas.
- Reverses: the grayscale-only rule for data marks, and DESIGN.md's "Food is photo only, no keyboard, ever", which went stale with D-035.

## D-097 Home cards follow GlanceCard; the Data card leads with last night's sleep and keeps the week's weight small

- Status: decided by Isaac, 2026-10-26, in the design system's walkthrough. It amends D-091, which had removed weight from Home.
- What: each card has three rows: area and time frame, one centred number with a small picture, and a detail row. There are no buttons inside cards; the card is the control.
  - Data: last night's time asleep, 7-night bars, "Usual", and the week's trend weight.
  - Food: today's kcal range, protein and meals.
  - Workout: sessions this week with Monday to Sunday dots, the next template and working sets.
- Display rule: Home shows two daily numbers, today's intake and last night's sleep.

## D-098 Sleep and Day follow the walkthrough: a fixed 14-night window, one overnight line, and a folding Day timeline with named places

- Status: decided by Isaac, 2026-10-26, in the design system. It amends D-094 and D-095.
- Sleep:
  - The window is fixed at 14 nights, with no 7/14/30 switch.
  - The bedtime and wake "usual" lines carry their own labels.
  - The stage times sit on the hypnogram's lanes, and wake-ups are written out.
  - Heart rate, breathing and HRV are one line of three numbers; the two range charts are gone.
- Day:
  - A summary sits at the top, with previous and next day arrows.
  - Empty hours fold to a thin band.
  - Sleep is a normal card with a stage stripe, not the black block.
  - There is no steps lane; steps go in the summary.
  - Places are named on the phone by reverse geocoding. The names never leave the phone: they are not synced and not logged.

## D-099 Food and Workout follow their walkthroughs: the match sheet with half-step servings, an inline rest, and a summary after Finish

- Status: decided by Isaac, 2026-10-26, in the design system.
- Food:
  - The camera's text sits on a scrim.
  - The match sheet shows totals first, in the data colours. Servings change in half steps, and Log is at the bottom.
  - The Food Today screen shows the day's ranges, the meals, and the week as daily bands.
- Workout:
  - The rest countdown sits inside the black logger card, with -15, +15 and Skip. Log never moves.
  - The next set shows last time's numbers as a dashed row.
  - The area nav is hidden while logging.
  - Finish opens a summary: duration, working sets, volume, In Health, and each exercise's best set against the last session of the same template. The summary has an Undo.
- Strength progress is history, not advice (D-032).

## D-100 Next is computed from the finished-workouts file by one core function; seeded history does not move it

- Status: proposed by night agent, 2026-10-26 (S-036).
- Problem: under D-089 Home and the Workout screen must show the same Next, the day after the session that finished last, but Home reads its inputs once per appearance from disk while the Workout screen keeps finished sessions in memory, and an Empty workout has no day to follow.
- Given: finished-workouts.json holds every `FinishedWorkout` with `endedAt` (D-056). `TemplateLibrary.next(after:)` already wraps and falls back to the first day for an unknown key. `AppEnvironment.workoutHistory` is synthetic `-uitest` sessions with no end time, used for last numbers (D-046).
- Constraints:
  - Computing Next in each view breaks "the same Next" as soon as one of them changes.
  - Counting the seeded `workoutHistory` sessions would change Next in every scenario that seeds them and the tests built on those scenarios, though the live app has none.
  - Following an Empty workout's key would reset the rotation to the first day after every empty session.
- Options:
  - (a) `WorkoutRotation.next(in:finished:)`: the finished session with the latest `endedAt` whose key is not nil or "empty" names the last day; `library.next(after:)` does the rest. Home passes the file, the Workout screen its loaded copy of the same file.
  - (b) Store a "last day" key in the template library at Finish.
  - (c) Rotate by weekday.
- Decision: (a). Nothing new is stored, so an off-schedule session moves Next once it is finished, and a removed template falls back to the first day. The `-uitest` scenario "rotation" writes one synthetic finished Day 1 session into the persisted store at launch, so Home and Workout read it the way the live app does.
- Evidence: Packages/StezuCore/Sources/StezuCore/WorkoutRotation.swift, App/Sources/HomeViewModel.swift, App/Sources/Workout/WorkoutView.swift, App/Sources/AppEnvironment.swift, WorkoutRotationTests (commit on wt/S-036).
- Reverse if: Isaac wants a weekday schedule (D-089), or sessions from other apps should count toward the rotation.

## D-101 Continue reopens the same `WorkoutSession` in the logger; Finish replaces it by id in the file and in Health

- Status: proposed by night agent, 2026-10-26 (S-036).
- Problem: under D-090 a finished session must reopen with its sets, take new ones, and finish again as the same session, with one copy on the phone, one workout in Health and one `workout_session` record on the server.
- Given: a session's id is `stezu.workout.<start ms>` (D-056) and set ids add the set's time (S-030), so both depend only on times already stored. The server keeps the newest `updated_at` per `(kind, id)`. `HealthKitStore.saveStrengthWorkout` skips an id already in Health. Finish appends to finished-workouts.json.
- Constraints:
  - A new session for the continuation breaks "same id" and makes two rows and two Health workouts.
  - Saving again without deleting leaves the old, shorter workout in Health, since the write skips a known id.
  - Making old sets undoable after Continue would need tombstones for sets the server already has.
- Options:
  - (a) `SetLogger(continuing:template:history:)` takes the finished session as is, puts the card on the first exercise with sets still to do, prefilled from its last set, and keeps old sets out of Undo. Finish goes through the same `keep`: `WorkoutRotation.keep` replaces the entry with the same id in place (else appends), the session record is queued again with a newer `updated_at`, and when the old copy was in Health, `WorkoutFinish.write(replacing:)` calls `HealthStore.deleteStrengthWorkout(externalID:)` before saving from the start to the new end.
  - (b) Link a second session to the first.
  - (c) Edit the finished entry in place without the logger.
- Decision: (a). Continue needs no workout in progress and a template still in the library; the logger file is saved while continuing as for any session, so a relaunch resumes it and its Finish still replaces by id.
- Evidence: Packages/StezuCore/Sources/StezuCore/SetLogger.swift, WorkoutRotation.swift, WorkoutFinish.swift, HealthStore.swift, App/Sources/Workout/WorkoutView.swift, WorkoutHistoryView.swift, HealthWorkoutReplace.swift, WorkoutRotationTests/testContinuedSessionKeepsIdAndAppendsSets (commit on wt/S-036).
- Reverse if: continuing older sessions is wanted (D-090), or HealthKit refuses the delete on device; then save the continuation as its own workout.

## D-102 Colour tokens are dynamic UIColors in one Swift file shared by the app and the extension, checked against tokens.json by G7

- Status: proposed by night agent, 2026-10-26 (infra/tokens-v2).
- Problem: every colour in design/system/tokens.json has a Light and a Dark value, the app and the RestActivity extension both draw with them, and the values must not drift from tokens.json, though Linux CI cannot build SwiftUI.
- Given: tokens.json lists 27 colours (two with alpha, one a reference to `ink`), 8 spacings, 4 radii, 6 sizes. project.yml compiles App/Shared into both targets; the extension has no asset catalog, and project.yml is outside an infra card that does not ask for it. G4 already reads every Swift file on Linux.
- Constraints:
  - Asset-catalog colorsets split the values over 27 Contents.json files, need a second catalog for the extension, and are JSON a reviewer cannot read side by side with tokens.json.
  - Keeping Theme.swift in App/Sources leaves the extension without tokens, so its countdown font stays a literal.
  - Values typed by hand drift from tokens.json with no compiler to notice.
- Options:
  - (a) App/Shared/Theme.swift: each colour is `Color(uiColor: UIColor { traits in ... })`, picking the Light or Dark 0xRRGGBB (and alpha) from `userInterfaceStyle` when the view draws. G7 parses tokens.json and fails unless Theme.swift has every colour, spacing, radius, size and type style with the same values, and greps App/Sources, App/RestActivity and App/Shared for `Color.white/black`, `.white/.black`, `Color(red:/hex:/white:/.sRGB`, 6-digit hex and `.system(size:` outside Theme.swift.
  - (b) Colorsets in Assets.xcassets, plus one in a new extension catalog.
  - (c) `@Environment(\.colorScheme)` switches in each view.
- Decision: (a). One file, readable next to tokens.json, no project change, and the extension shares it. `UIColor` drawing in PhotoSource (the synthetic plate's pixels) is not UI and is outside the grep (`UIColor.white` does not match `\bColor`).
- Evidence: App/Shared/Theme.swift, scripts/gate-linux.sh (g7_token_lint), App/RestActivity/RestActivityWidget.swift (commit on infra/tokens-v2).
- Reverse if: a designer wants to edit colours in Xcode's catalog editor, or tokens.json gains a high-contrast variant (then colorsets carry the extra appearance natively).

## D-103 Type styles are one view modifier that scales a fixed size with `@ScaledMetric(relativeTo:)`

- Status: proposed by night agent, 2026-10-26 (infra/tokens-v2).
- Problem: the 11 type styles (t-hero to t-axis) must follow Dynamic Type, keep their exact default sizes, weights and tracking, and give numbers tabular digits, while v1 set every font as `.system(size:)`, which never scales.
- Given: some styles match an iOS text style at the default size (17 headline, 15 subheadline, 12 caption 1, 11 caption 2), others do not (76, 42, 28 medium). `Font.system(size:)` has no `relativeTo:`; `Font.custom(_:size:relativeTo:)` needs a font name. Tracking is a view modifier, not part of `Font`.
- Constraints:
  - Built-in text styles (`.headline`, `.body`) cover only some sizes and carry their own weights and tracking.
  - A `Font` computed once from `UIFontMetrics` does not update when the text size changes while the app runs.
  - A style without its tracking lets the big numbers drift from v1, which applied `bigNumberTracking` by hand next to each font.
- Options:
  - (a) `View.textStyle(_:weight:)`: a ViewModifier holding `@ScaledMetric(wrappedValue: size, relativeTo: style's iOS text style)`, which SwiftUI updates on a text size change, then `.font(.system(size: scaled, weight:))`, `.monospacedDigit()` for number styles and `.tracking` when the token has one. `weight:` overrides the style's weight where v1 had a medium or semibold variant.
  - (b) `Font` statics using built-in text styles where they match and `Font.custom("", size:relativeTo:)` elsewhere.
  - (c) `@ScaledMetric` properties in each view.
- Decision: (a). Every font outside Theme.swift is now `.textStyle(...)`; the size, relative style, weight, tracking and tabular flag of each style live in `Theme.TextStyle` and G7 checks their sizes, weights and tracking against tokens.json.
- Evidence: App/Shared/Theme.swift (`Theme.TextStyle`, `ThemeTextStyle`), every view in App/Sources, App/RestActivity/RestActivityWidget.swift (commit on infra/tokens-v2).
- Reverse if: a style needs a line height (tokens.json has them; SwiftUI applies them only as `lineSpacing`), or Text concatenation needs styled `Text` values, since the modifier returns a view.

## D-104 Every sheet closes or steps back through `dismiss` from a text button in its TopBar; History's navigation bar is hidden

- Status: proposed by night agent, 2026-10-27 (S-038).
- Problem: sheets put their Done in different places (a toolbar item in Workout History, a row button in Metric, an HStack in Sources and Food history, none in Settings, Exercises, Weigh-in, the meal editor or the Matching sheet), and on iOS 26 a toolbar item is drawn as a floating glass pill, which is the shadowed Done Isaac flagged.
- Given: `@Environment(\.dismiss)` closes a sheet when read in its root view and pops a page when read in a view pushed onto a NavigationStack. Workout History is a NavigationStack inside a sheet, three pages deep. Metric steps back through local state (`openDay`, `openWeek`), not navigation.
- Constraints:
  - A toolbar item for Done brings the glass pill back.
  - Hiding History's navigation bar removes the system back button and the edge swipe back, so every page needs its own way back.
  - A Done that runs anything but `dismiss` (or the same state reset as before) would change behaviour, which the card rules out.
- Options:
  - (a) One `TopBar` view (AppShell.swift): an optional Home closure, an optional text action (title, id, closure) and the title beneath. Sheets pass Done -> `dismiss()`, or the rung above (Metric's "8 weeks" and "Week", History's previous page) -> the same state change as before; History hides its navigation bar and each page is a `HistoryPage` whose rung calls that page's own `dismiss`, which pops, or closes the sheet on the first page.
  - (b) Keep the navigation bar in History with a custom plain back button as a toolbar item.
  - (c) A sheet wrapper that adds Done around any content.
- Decision: (a). Swipe down still closes every sheet: none sets `interactiveDismissDisabled`, and every sheet now shows the drag indicator.
- Evidence: App/Sources/AppShell.swift (`TopBar`, `AreaScaffold`), App/Sources/Workout/WorkoutHistoryView.swift (`HistoryPage`), App/Sources/Data/MetricDetailView.swift (`rung`), App/UITests/SheetHeaderUITests.swift (commit on wt/S-038).
- Reverse if: History needs the edge swipe back (then (b) with the bar's background hidden), or a sheet gets unsaved edits that Done must confirm.
