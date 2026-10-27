# SetLogger

The workout's `invert` card: the exercise, which set this is, last time's numbers, the weight and reps steppers and the Log button, so one tap logs a prefilled set.

## Use
- Exercise name in `t-title-2`, "Set 3 of 4" in `t-subtitle`, the rep range and "Last 135 x 8, 7d ago" in `t-label`/`on-invert-muted`.
- Log is the full-width primary pill at the bottom of the card, where the thumb rests. BW sits to its left as an outline pill.
- While resting, the countdown sits inside the card above the steppers (RestTimer, inline) so the Log button never moves.
- The ellipsis menu holds Swap and Skip exercise.

## Consumer provides
Exercise, set index and count, rep range, last numbers, weight and reps, rest state, handlers.

## Don't
Add a keyboard field, a confirmation, or anything below Log inside the card.
