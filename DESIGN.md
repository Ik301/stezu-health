# Design

The visual source of truth is the Ingest design system in `design/system/` (adopted in D-096). Start with `design/system/AGENTS.md`. It covers:

- `README.md`: principles, copy, colour, type and spacing.
- `tokens.json`: Light and Dark values.
- `components/<Name>/README.md`: 23 components.
- `walkthroughs/*.html`: the clickable screens for Home, Data, Food and Workout.

All numbers in it are synthetic. Never replace them with personal data (D-034). The app defines the tokens in one place, App/Sources/Theme.swift. The table at the end of design/system/README.md maps each v1 value to its token.

## Rules that must survive into code

- One black (`invert`) surface per screen: the next thing to do.
- Missing data is "--", never 0. A rest day in Workouts is a real 0; a missing night or weigh-in is not.
- Food energy and protein are ranges with an en dash ("1,080–1,440 kcal").
- Colour is data only: `data-energy`, `data-protein`, `data-heart`, `sleep-*`. Chrome stays `ground`, `surface`, `ink` and `muted`. No red or green judgement.
- No scores, rings, targets or suggestions (D-032). Sleep, HRV and the strap readings are labelled context.
- Home cards have no buttons inside them; the whole card is the control.
- Every text pair meets 4.5:1 in Light and Dark. Light and Dark follow the phone. Type scales with Dynamic Type.
- No shadows. Every tap target is at least 44 x 44; a row that opens something is a button across its whole width.
- Keep the accessibility ids the tests use (`home.card.<area>`, `screen.<area>.title`, `nav.home`, `nav.circle.<area>`).

## App icon

- Name on the home screen: Ingest.
- Icon: the Home screen itself. Three stacked cards on a #D6D6D6 ground. The middle card is #0B0B0B (the inverted "log this now" card); the other two are #F6F6F6 with a white border. Cards are 600 x 168 on the 1024 canvas, radius 46, 34 apart.
- Source: design/AppIcon.svg. Built asset: App/Sources/Assets.xcassets/AppIcon.appiconset (one 1024 px RGB PNG, no alpha).

## Tap budgets

- 0 taps to see today's totals and last night's sleep (Home).
- Food: one tap to the camera, one to shoot, one to Log. Text search and barcode are one tap away for food the camera can't see (D-035). No keyboard on the photo path.
- 1 tap to log a set.

## Display rule

- Weekly numbers by default. Two daily numbers on Home: today's intake and last night's sleep (D-097). Weight is weekly.
- No composite daily score.
- HRV, sleep and the strap readings are context only.

## Scrolling

No scroll bars anywhere. Every `ScrollView` uses `.scrollIndicators(.hidden)`, and the app root sets it too, so new screens inherit it.
