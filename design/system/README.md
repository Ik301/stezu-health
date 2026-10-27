Ingest is a quiet, monochrome iPhone app for the health data you enter by hand (meals, sets, weigh-ins) and the data your wearable writes to Apple Health. Logging takes one tap; reading goes as deep as you want, one tap per level. The system has two jobs and keeps them apart: chrome is black, white and grey so the next action is obvious, and colour is reserved for data, so a chart can say a lot without the screen getting loud.

Build with: `tokens.json` (colours in Light and Dark, the SF Pro type scale, spacing, radii, sizes), `components/bundle.css` (the components as classes), `components/bundle.js` (chart helpers, `window.Ingest`). SwiftUI names for every token are in the mapping table at the end.

## Principles

1. **One black thing per screen.** `invert` marks the single next action: the Home card for this moment, the set logger, the Log button, the active nav circle. Zero is fine. Two is a bug.
2. **Every number is a door.** Values sit on a ladder: Glance (Home card) → Week (Data row) → Metric (8 weeks) → Days → Day (timeline) → Record (source). Each rung is one tap on the whole row, and back is one tap. Logging never goes below the first rung.
3. **Absent is not zero.** Missing data is "--" in the same style the value would have had. Charts draw an absent week as a dashed `track` slot, never a zero-height bar. Every weekly figure carries its coverage ("5 of 7 days").
4. **Estimates are ranges.** Food energy and protein are always "620–780 kcal": an en dash, lows and highs summed separately. Charts draw a band with a midpoint.
5. **Colour is data, never chrome.** Hue appears only in chart marks, their legends and the numbers they explain. Each hue means one quantity everywhere: `data-energy` is always kcal, `data-heart` is always heart rate.
6. **Context, not verdicts.** Sleep, HRV, blood oxygen, respiratory rate and temperature carry a `context` tag. No scores, no targets, no red or green judgement of a day (D-032).
7. **Thumbs log, eyes read.** Logging controls live in the bottom half of the screen. Reading screens put the chart at the top and the list under it.

## Content

- Plain, short, sentence case. No exclamation marks, no emoji, no "Oops". Say what happened and where it went: "Lunch logged, in Health". "Could not save the meal."
- Name things the way Isaac would: "Weigh in", "Resume", "Last night", "This week". Not "Sync record", "Session object".
- Numbers: units lower case after a space ("57 bpm", "172.4 lb"), thousands with a comma ("8,140"), durations as "7h 12m", sets as "135 x 8", ranges with an en dash ("1,240–1,480"). Weeks run Monday to Sunday and are written "Oct 13 to 19".
- Coverage is words plus dots: "6 of 7 days", "4 of 7 nights", "31 samples".
- Confidence is a level and a reason: "Medium, 5 weigh-ins".
- Waiting states say when they will resolve: "Pending, will match when online". Never show 0 for something that has not happened.

## Colour

- Page on `ground`; cards on `surface` with a 1 px `edge`; pills, inputs and sheets on `surface-raised`.
- Text in `ink`; labels, coverage, sources and axis text in `muted`. On `invert`, text is `on-invert` and labels `on-invert-muted`.
- `invert` is the one black (in Dark, the one light) surface per screen.
- Chart marks: `data-trend` for any derived line (2 px), `data-sample` for raw dots under it, `data-energy` and `data-protein` for food (each with a `-band` for its range), `data-heart` for heart rate, `sleep-deep`, `sleep-core`, `sleep-rem`, `sleep-awake` for stages. Steps, sets and weight are `ink`.
- `data-energy` and `data-protein` share a lightness, so never overlay them in one plot: give each its own panel or row.
- `signal-pending` and `signal-error` are for words about state, never for data. A failed write says "Not in Health" in `signal-error`; a high heart rate is still `data-heart`.
- `track` is decorative: gridlines, empty coverage dots, absent-bar outlines.
- On the camera: `camera` behind the preview, `on-camera` for the shutter, and every piece of text on a `camera-scrim` band or a solid surface.
- Dark is a real theme, not an inversion: `ground` #111111, `surface` #1a1a1a, `invert` turns light. Every text pair holds 4.5:1 in both themes; `sleep-rem` in Light (2.7:1) is the one mark under 3:1, and its row and label carry the meaning.

## Type

SF Pro through the system font; no custom faces. Sizes are iOS text styles so they scale with Dynamic Type (`.font(.system(.body))` or `relativeTo:` for the custom sizes).

- `t-hero` (76) for the rest countdown only. `t-big` (42, tracking -1) for the Home card value, stepper values and the weight trend. `t-stat` (28) for secondary figures on detail screens. All tabular digits.
- `t-title-1` (34 semibold) for screen titles; `t-title-2` (28 semibold) for the exercise name.
- `t-headline` (17 semibold) for row titles and every button; `t-value` (17 medium) for row values; `t-body` (17) for explanations; `t-subtitle` (15) for card subtitles and set rows.
- `t-label` (12) in `muted` for every label. `t-axis` (11 medium) for chart text only.
- One `t-big` or `t-hero` per card. Never bold a label to make it louder; move it up the scale instead.

## Spacing, radius, size

- Screen gutter and card padding `space-lg` (16). Cards that carry a big number use `space-card` (18). Cards in a stack and rows in a card: `space-md` (12). Label to value inside a Home card: `space-xs` (4).
- `radius-card` (18, continuous) on every card; `radius-inner` (12) for a surface inside a card; `radius-chip` (8) for tags; `radius-pill` for buttons, the segmented switch, search and toasts.
- Every tap target is at least `size-target` (44 x 44). Stepper and rest buttons `size-control` (48). Nav circles `size-nav` (58). Shutter `size-shutter` (74).
- No shadows. Depth comes from `ground` → `surface` → `surface-raised` and from sheets.

## Layout

- Home: a gear top right, then three GlanceCards filling the height. Never scrolls.
- Area screens: TopBar, a `t-title-1` title, content, AreaNav at the bottom (Food uses the camera's own bottom bar).
- Detail screens are sheets with a drag indicator: TopBar with Done or the rung above it, title, chart well, list, then sources and method at the bottom.
- No scroll indicators anywhere.

## Charts

- Draw to scale and label only values the chart reaches. Two light gridlines; exact values live in the list under the chart, so axes stay sparse.
- A main chart is `size-chart` tall in a `surface` well; a row sparkline is 72 x `size-spark`.
- Missing data breaks a line or leaves a dashed slot. Never interpolate across a gap, never draw zero.
- The newest point or week is emphasised (full strength, end dot); older ones step back (55%).
- In SwiftUI use Swift Charts (a system framework, so not a new dependency) and give every chart an `accessibilityChartDescriptor` so VoiceOver can play it as an Audio Graph.

## Motion

Sheets and toasts use the system spring. Numbers change in place without counting animations. The rest countdown ticks once a second with tabular digits. With Reduce Motion on, sheets cross-fade.

## Iconography

SF Symbols only, and few of them: `house` (Home), `gearshape` (Settings), `chevron.right` (depth), `ellipsis` (exercise menu), `magnifyingglass` (search). 17 pt medium, `ink`. The three areas are always words, never icons. No emoji anywhere. The app icon is the Home screen itself (design/AppIcon.svg) and is not redrawn here.

## Accessibility

- Contrast: 4.5:1 for all text in both themes; 3:1 for marks that carry meaning. v1's #8a8a8a label was 3.0:1 and is replaced by `muted`.
- Focus: 2 px `focus` ring, offset 2 px; on `invert` the ring uses `ground`.
- Every Home card is one VoiceOver element ("Food, Today, 2 meals, 1,240 to 1,480 kcal"); its action pill is the next element.
- Coverage dots and colours always have words beside them.
- Keep the accessibility ids from CLAUDE.md (`home.card.<area>`, `screen.<area>.title`, `nav.home`, `nav.circle.<area>`) on whatever replaces a control.

## SwiftUI mapping

| Theme.swift (v1) | Token (v2) | Change |
| --- | --- | --- |
| `background` #E6E6E6 | `ground` | adds Dark #111111 |
| `card` #EFEFEF | `surface` | adds Dark #1A1A1A |
| `cardBorder` white | `edge` | adds Dark #2C2C2C |
| `Color.white` (13 literals) | `surface-raised` | new token |
| `invertedCard` #0B0B0B | `invert` | Dark #F2F2F2 |
| `invertedText` white | `on-invert` | Dark #0B0B0B |
| `label` #8A8A8A | `muted` #5E5E5E | contrast 3.0 → 5.6 |
| `text` #0B0B0B | `ink` | Dark #F2F2F2 |
| `cardRadius` 18 | `radius-card` | same |
| `labelSize` 11.5 | `t-label` 12 | Caption 1, scales |
| `subtitleSize` 15 | `t-subtitle` | same |
| `bigNumberSize` 42 / tracking -1 | `t-big` | same |
| `heroNumberSize` 76 | `t-hero` | weight 500 as coded |
| `navCircleSize` 58 | `size-nav` | same |
| 17 semibold (23 literals) | `t-headline` | new token |
| 34 / 28 semibold literals | `t-title-1`, `t-title-2` | new tokens |
