# MealItem

One identified food in the meal sheet: its name (tap to replace), where it came from, servings in half steps, and its energy and protein ranges.

## Use
- On `surface-raised` with `radius-inner`, stacked with `space-sm` gaps inside the sheet.
- Name in 17 semibold with a `track` underline that says "tap to replace". Source as a Tag (dining hall, restaurant, package, text estimate).
- Servings stepper: 44 pt buttons, half steps, never below 0.5. Swipe left removes.
- Ranges use `data-energy` and `data-protein` for the numbers only; the rest is `ink`/`muted`.
- The sheet totals at the top sum the lows and the highs; the Log pill sits at the bottom.
