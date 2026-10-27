# Ingest design system: start here

This folder is the design system and the UI walkthroughs for Ingest (the Stezu Health iPhone app, repo ik301/stezu-health). It is design input, not code to ship: build the SwiftUI screens from it, keep using the repo's own CLAUDE.md, features.json and gates for how work is done.

## Read in this order

1. `README.md`: the brand book. Principles, copy rules, colour, type, spacing, charts, accessibility, and the table mapping every v1 `Theme.swift` value to its token.
2. `docs/walkthrough.md`: the four flows, tap counts, and the decisions taken on 2026-10-27.
3. `tokens.json`: every token with a usage note. `tokens.css` is the same, compiled to CSS custom properties (Light, Dark, and a `prefers-color-scheme` fallback).
4. `components/<Name>/README.md`: when to use each component, what it needs, what not to do.
5. `docs/audit.md` (what v1 ships and where it drifts) and `docs/analysis.md` (what can replace Zepp and Health, and a build order) when planning.

## Files

| Path | What |
| --- | --- |
| `README.md` | Brand book and Theme.swift mapping |
| `tokens.json`, `tokens.css` | Colour (Light, Dark), type scale (SF Pro), spacing, radius, size |
| `components/<Name>/README.md` | Guidelines for 23 components |
| `components/<Name>/preview.html` | A live preview; open it in a browser (uses `../../tokens.css`, `../bundle.css`, `../bundle.js`) |
| `components/bundle.css`, `bundle.js` | The preview styles and chart helpers (web only; not for the app) |
| `walkthroughs/home.html`, `data.html`, `food.html`, `workout.html` | Interactive phone walkthroughs, one per flow, each with notes on every screen. Self-contained |
| `walkthroughs/all-screens.html` | Every screen in one page |
| `docs/` | Audit, walkthrough guide, Zepp and Health analysis |

## Rules that must survive into code

- One black (`invert`) surface per screen: the next thing to do.
- Missing data is "--", never 0. A rest day in Workouts is a real 0; a missing night or weigh-in is not.
- Food energy and protein are ranges with an en dash ("1,080–1,440 kcal").
- Colour is data only: `data-energy`, `data-protein`, `data-heart`, `sleep-*`. Chrome stays `ground`, `surface`, `ink`, `muted`.
- No scores, rings, targets, suggestions or red/green judgement (D-032). Sleep, HRV and the strap readings are labelled context.
- Home cards have no buttons inside them; the whole card is the control.
- Every text pair meets 4.5:1 in Light and Dark. Use `muted` (#5e5e5e / #a3a3a3), not v1's #8a8a8a.
- Light and Dark follow the phone. No scroll indicators.
- Keep the accessibility ids the repo's tests use (`home.card.<area>`, `screen.<area>.title`, `nav.home`, `nav.circle.<area>`).

## Decisions to record in the engineering system before building

- **Home Data card leads with last night's sleep**, with the week's trend weight small underneath. DESIGN.md currently says the only daily number is today's intake, so this needs a decision record.
- **DESIGN.md's "Food is photo only, no keyboard, ever"** is stale since D-035 (text search). Reword it.
- **Known v1 bug:** the workout rotation never advances (`library.next(after: nil)` in HomeInputs and WorkoutView), so "Day 3 next" in the walkthroughs assumes it is fixed.

## Not designed yet

Barcode, Search results, meal editing, Swap exercise, the workout History list, Settings. They appear as tap-through notes in the walkthroughs.

All numbers in the previews and walkthroughs are synthetic. Do not replace them with personal data (D-034).
