# Card

The one container: a `surface` fill, a 1 px `edge` border and `radius-card` corners on `ground`; the inverted variant marks the single next action on a screen.

## Use
- Group one subject per card: a metric family, a rest timer, a logged set. Stack cards with `space-md` between them, padding `space-lg` (`space-card` for cards that carry a `t-big` number).
- `ig-card--invert` (`invert` fill, `on-invert` text, no border) is for the one thing to do next. One per screen; zero is fine, two is a bug.
- No shadows. Separation comes from `surface` sitting one step above `ground` and from the `edge` highlight.

## Consumer provides
Children. Optional `--invert`, `--big` (18 px padding), `--tight` (4 px gaps).

## Don't
- Nest a card in a card. A surface inside a card uses `radius-inner` and `surface-raised` (see MealItem) or `ground` (chart wells).
- Use invert for emphasis, status or errors.
