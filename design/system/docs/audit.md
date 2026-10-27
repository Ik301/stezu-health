# What v1 actually ships

An audit of App/Sources against DESIGN.md and Theme.swift, at branch claude/gifted-dirac-e3dqra. The identity is good and worth keeping. The implementation of it has drifted, and three things block the "in depth" goal outright.

## The extracted system

Theme.swift defines 7 colours and 7 sizes, all light-only:

| Token | Value | Uses |
| --- | --- | --- |
| background | #E6E6E6 | every screen |
| card | #EFEFEF | every card |
| cardBorder | #FFFFFF | Home cards, nav circles |
| invertedCard | #0B0B0B | black card, logger, primary pills |
| invertedText | #FFFFFF | text on black |
| label | #8A8A8A | 26 labels |
| text | #0B0B0B | 47 places |
| cardRadius / labelSize / subtitleSize | 18 / 11.5 / 15 | |
| bigNumberSize / tracking / heroNumberSize | 42 / -1 / 76 | |
| navCircleSize | 58 | |

Components that exist in code (each re-implemented per view, none shared beyond HomeCardView, NavCircle, AreaScaffold and MetricOpenButton): Home card, nav circles, area scaffold, pill button (three private copies), segmented Photo/Barcode switch, stepper, Log card, rest card, logged set row, shutter, undo toast, meal item list, metric row, metric detail (weeks list, days list), trend chart (Canvas, weight only), day record list, empty state.

## Drift from the tokens

- **Type outside the scale.** 17 semibold appears 23 times and 17 medium 11 times as literals; 34, 28 and 24 point titles are literals too. The scale in Theme.swift covers about half of what is on screen.
- **Colour outside the tokens.** `Color.white` 13 times (pills, segmented track, shutter), `Color.black` once (camera). These need tokens before a Dark theme is possible.
- **Spacing is free-form.** Paddings of 2, 3, 6, 8, 10, 12, 14, 16, 18, 20, 24; stack spacings of 0, 2, 4, 6, 8, 10, 12, 14, 16, 24. 16 and 12 dominate, which is what the v2 scale keeps.
- **DESIGN.md says hero numbers are semibold; the code uses medium.** v2 follows the code.
- **DESIGN.md says "No keyboard, ever" for Food.** D-035 added text search. The rule is stale.

## Problems that matter

1. **Labels fail contrast.** #8A8A8A is 3.0:1 on cards and 2.77:1 on the background; WCAG AA needs 4.5:1. At 11.5 pt, in a gym, on a phone at arm's length, this is the most-read text in the app (coverage, sources, confidence, "Last 135 x 8").
2. **No Dynamic Type.** Every font is `.system(size:)` with a fixed number, so the app ignores the text size setting.
3. **No Dark mode.** Hex literals everywhere and no asset-catalog colours. The app is a white slab at 23:00 when you check sleep.
4. **Depth targets are too small.** The row chevrons that open a metric are 44 x 22. The rows themselves are not buttons.
5. **Only one chart.** Weight gets a Canvas trend line; steps, sleep, HRV, resting HR, food and workouts are text lists. "In depth" needs pictures, and there is no chart component to reuse.
6. **No daily view of wearable data.** By rule (DESIGN.md display rule) Data is weekly only. Last night's sleep, the thing people open Zepp for each morning, cannot be shown.
7. **The rotation never advances.** `library.next(after: nil)` in HomeInputs and WorkoutView means the Workout card always offers the first template. This is a bug, not a style issue, and it undermines the black card.
8. **Text over the camera.** The today strip and error messages are white text drawn straight on the preview; on a white plate they disappear.
9. **Finish is irreversible.** One tap, no confirmation (by design) and no undo. Keep the one tap, add the undo.

## What to keep

The ground/surface/invert trio, the one black card, "--" for absent, coverage beside every number, ranges for food, steppers instead of a keyboard, one tap per set, the three-card Home that doubles as the app icon. These are the system; v2 builds on them rather than replacing them.
