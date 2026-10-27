# RestTimer

The rest countdown that starts by itself after Log, with -15 s, +15 s and Skip; mirrored on the lock screen as the RestActivity Live Activity.

## Use
- Standalone card (`surface`) with `t-hero` digits when the logger is scrolled away or on the lock screen; inline chip inside SetLogger otherwise.
- Adjusting keeps the start time; Skip removes it. At zero the card disappears and a haptic plays; no sound by default.
- Tabular digits so the number does not jitter.
