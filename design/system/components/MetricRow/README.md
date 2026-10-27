# MetricRow

A row on the Data overview: name, context tag, coverage, a 7-day sparkline and the week's value; the whole row opens that metric's detail.

## Use
- Grid: title block, 72 x 28 sparkline, value, chevron. Rows in one card, separated by 1 px `track` rules.
- The whole row is the button (v1's 44 x 22 chevron is too short to hit). The chevron only signals depth.
- Sparkline: daily values Monday to Sunday, line for levels (weight, HR, HRV), bars for counts (steps). Missing days break the line or show an empty slot; never a dip to zero.
- Food uses `data-energy` for its sparkline; everything else is `ink`.
- Value: the weekly figure (mean, median or trend, as the metric's note says) in `t-value`.

## Order
Body (weight), Activity (steps, workouts), Food, Recovery context (sleep, HRV, resting HR), Strap context (blood oxygen, respiratory rate, temperature), Places.
