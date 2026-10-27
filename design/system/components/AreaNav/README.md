# AreaNav

Three 58 pt circles at the bottom of every area screen, Data, Food and Workout, with the current area in `invert`.

## Use
- Sits at the bottom edge on `ground`, `space-xl` between circles. One tap moves between areas; Home is the house button top left.
- Words, not icons: the three areas are named the same on Home and here.
- The current circle has `aria-current="page"` and VoiceOver value "active".

## Don't
- Add a fourth circle. Settings stays behind the gear on Home; History lives inside its area.
- Hide it on Food. The camera screen keeps its own bottom bar (shutter), so Food uses the top-left Home button instead, as in v1.
