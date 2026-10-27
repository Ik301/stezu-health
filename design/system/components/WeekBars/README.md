# WeekBars

Eight weekly bars, oldest on the left, each labelled with its week and coverage; the main chart on every metric detail screen.

## Use
- Counts and means as solid bars in the metric's colour; the current week at full strength, past weeks at 55%.
- Estimates (food) as a `-band` box from low to high with a 3 px midpoint bar.
- A week without data is a dashed `track` slot with "--" above it: absent is not zero.
- Two light gridlines, no y-axis numbers; the exact values are in the list under the chart.
- Tap a bar to open that week's days (the same as tapping its row in the list).
- In SwiftUI: Swift Charts `BarMark` (system framework, no new dependency), with `accessibilityChartDescriptor` for Audio Graphs.
