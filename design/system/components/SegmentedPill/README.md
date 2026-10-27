# SegmentedPill

A two or three way switch in a `surface-raised` capsule; the chosen segment is `invert`.

## Use
- Mode switches that keep you on the same screen: Photo / Barcode on the camera, 8 weeks / Days on a metric.
- Labels 12 px medium; each segment at least 38 pt tall inside a 44 pt track.
- Each segment is a toggle button with `aria-pressed` (v1 sets accessibilityValue "on"/"off").

## Don't
Use it for navigation between areas (AreaNav) or for more than three options.
