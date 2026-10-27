# WeightChart

Weigh-in dots and the trend line over eight weeks: the raw samples in `data-sample`, the EWMA trend (alpha 0.1, gap-weighted as in SPEC.md) in `data-trend`.

## Use
- The trend is the number people read; the dots show how noisy the scale is. The last trend point gets a 4 px dot with a `surface` ring.
- Three gridlines labelled in whole pounds on the left, week starts as ticks.
- Days without a weigh-in draw nothing. The trend line does not interpolate dots that don't exist.
