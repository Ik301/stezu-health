# Replacing Zepp and Health

The goal is to stop opening Zepp and Apple Health to look at data. That is achievable for viewing. It is not achievable for collecting, and the design should not pretend otherwise.

## What cannot move

- **Zepp stays the pipe.** The strap talks to the Zepp app, and Zepp writes to Apple Health. Ingest reads Health. If Zepp is not running and syncing, Ingest has nothing new. You will still open Zepp for pairing, firmware, strap settings and the occasional forced sync.
- **Only what Zepp writes to Health exists for Ingest.** Check Health → Browse → each type → Data Sources & Access → Zepp. Zepp's own scores (PAI, stress, readiness-style scores) are, as far as I know, not written to Health, so Ingest cannot show them and should not imitate them. Sleep stages are only drawable if Zepp writes stage values rather than one "asleep" block; verify on the device before building the hypnogram.
- **No composite score.** DESIGN.md and D-032 rule out a daily score. That is a real difference from Zepp, and a good one: the app shows the inputs and lets you judge.

## The views that replace the visits

| You open Zepp or Health to... | Ingest view | Data (HealthKit) | Status |
| --- | --- | --- | --- |
| See last night's sleep | Home Data card, Sleep detail (window, stages) | sleepAnalysis with stage values | new; decided 2026-10-27, record it in the engineering system |
| Check resting HR and HRV trend | MetricRow → WeekBars | restingHeartRate, heartRateVariabilitySDNN | rows exist; charts new |
| See a day's heart rate | DayTimeline | heartRate samples | new |
| Count steps | MetricRow, WeekBars, hourly bars in DayTimeline | stepCount (statistics query) | rows exist; charts new |
| Look at strap readings | MetricRow + detail | oxygenSaturation, respiratoryRate, temperature | rows exist (S-027); detail new |
| See a workout's HR | Workout history page, HR lane on the Day view | heartRate during the workout's interval | new |
| Weight trend | WeightChart | bodyMass + Ingest's weigh-in store | exists |
| Food over time | WeekBars with ranges | Ingest's meals | rows exist; charts new |

## Strength analysis: the part Zepp does not do

This is where Ingest can be better than both apps, because it owns the set data. All of it is history, not advice, so it stays inside D-032.

- Per exercise: best set by session and estimated 1RM over time (Epley, shown with "estimate" and the set it came from as its confidence).
- Per week: working sets per muscle group, as WeekBars.
- Per session: sets and volume against the last session of the same template, in the history page.

## Build order

1. Swift Charts components: WeekBars, then WeightChart ported from the Canvas, then DayTimeline. Everything else reuses them.
2. Whole-row taps and the detail template for every metric, strap metrics included.
3. Record the sleep decision, then the Home Data card and the Sleep detail.
4. Day view timeline over the existing DayRecords.
5. Strength history pages.

Dark mode, the contrast fix and Dynamic Type are token changes in Theme.swift plus the literal clean-up; do them before step 1 so every new screen is born on tokens.
