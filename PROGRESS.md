# Progress

Newest entry first. One entry per card: the date, the card, what changed, the gate result and what comes next.

## 2026-10-25 Scaffold

- Added SPEC.md, DESIGN.md, AGENTS.md (CLAUDE.md links to it) and features.json with F-001 to F-010, none passing.
- StezuCore holds a placeholder `StezuCore.version` with one test. The app holds a placeholder HomeView with one AppTests test.
- Gates G1 to G4 live in scripts/gate-linux.sh. CI runs linux-core (required) and ios (advisory).
- Next: F-001, trend weight EWMA over irregular gaps.
