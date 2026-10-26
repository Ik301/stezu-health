# Design

Tokens for every screen. All text uses the system font (SF Pro). Colors are sRGB hex. The app defines these tokens in one place, App/Sources/Theme.swift.

## App icon

- Name on the home screen: Ingest.
- Icon: the Home screen itself. Three stacked cards on a #D6D6D6 ground, the middle one #0B0B0B (the inverted "log this now" card), the other two #F6F6F6 with a white border. Cards 600 x 168 on the 1024 canvas, radius 46, 34 apart.
- The ground is one step darker than the app background (#E6E6E6) so the light cards still read at 29 pt.
- Source: design/AppIcon.svg. Built asset: App/Sources/Assets.xcassets/AppIcon.appiconset (one 1024 px RGB PNG, no alpha; iOS makes the smaller sizes).

## Surfaces

- Background: #E6E6E6.
- Card: #EFEFEF fill, 1 px white border, corner radius 18.
- Inverted "log this now" card: #0B0B0B fill with white text.

## Type

- Labels: 11.5 pt, #8A8A8A.
- Big numbers: 42 pt, medium weight, tight tracking.
- Hero numbers: about 76 pt, semibold.

## Controls

- Pill toggles: white, with a black "on" state.
- Bottom nav on sub-screens: three 58 pt circles (Data, Food, Workout). The active one is black.

## Home

- Three tall cards: Data, Food and Workout. Each has a label, a subtitle and a big number.
- Time of day decides which card is the black one.
- Missing values show "--". Absent is not zero: never show 0 for missing data.

## Tap budgets

- 0 taps to see today's totals.
- Food is photo only: the shutter, then one Log tap. No keyboard, ever.
- 1 tap to log a set.

## Display rule

- Weekly numbers by default. Daily numbers only for today's intake against the target.
- No composite daily score.
- HRV and sleep are context only.
