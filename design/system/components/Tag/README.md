# Tag

A small outlined chip for facts about a value: that it is context only, where it came from, how sure it is, or that it is waiting.

## Use
- `context` on HRV, sleep, blood oxygen, respiratory rate and temperature: shown, never acted on.
- Source: "Ingest", "Health", or the writing app ("Zepp"). Records in a Day view always carry one.
- Confidence: level and reason ("Low, 2 weigh-ins").
- Pending in `signal-pending`, failures in `signal-error`. Both are words; colour only reinforces.
- 11 px medium, `radius-chip`, 1 px `track` border. Never filled.
