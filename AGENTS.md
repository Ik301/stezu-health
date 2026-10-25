# Agents

Read this first. SPEC.md says what to build, DESIGN.md how it looks, DECISIONS.md why. features.json is the work list, and each card works on exactly one feature.

## Layout

- Packages/StezuCore: a pure Swift package that holds all logic. No SwiftUI, UIKit or HealthKit imports and no `#if` platform branches. It builds and tests on Linux.
- App/Sources: the thin SwiftUI app (target StezuHealth, bundle ID com.ik301.stezuhealth, iOS 17). Views and wiring only.
- App/Tests: the AppTests unit tests. They run in the macOS CI job only.
- project.yml: the XcodeGen spec. The .xcodeproj is generated and gitignored.
- scripts/: the gates. .github/workflows/ci.yml: CI. PROGRESS.md: the log.

## Build and test

Core, on Linux or macOS:

    cd Packages/StezuCore && swift build && swift test
    swift test --filter StezuCoreTests.VersionTests/testVersionIsSet

App, on macOS (CI picks the simulator dynamically; see ci.yml):

    xcodegen generate
    xcodebuild test -project StezuHealth.xcodeproj -scheme StezuHealth \
      -destination 'platform=iOS Simulator,name=<an installed iPhone>' CODE_SIGNING_ALLOWED=NO

## Gates

Work on a branch named wt/F-xxx (night cards run in a worktree under .worktrees/<id>/). Run the Linux gates from the checkout or worktree root before every push:

    scripts/gate-linux.sh                 # FEATURE_ID=F-xxx overrides the branch name

- G1: `swift build && swift test` in Packages/StezuCore.
- G2: `scripts/check-features.py --base origin/main`. Only the card's feature entry may change, and only its `passes` field. passes:true needs every listed test to exist under Tests/. On main it only validates the schema.
- G3: `scripts/diff-budget.sh origin/main`, against the merge base, counting uncommitted and untracked files too. At most 300 changed non-test lines and 12 files (*.md and Tests/ excluded). No change to *.xcodeproj or *.entitlements, no signing keys in project.yml, and no test file may lose a `func test`. Skipped on main.
- G4: `swift format lint --strict` over all Swift files. Skipped with a notice if swift-format is missing. Fix with `swift format -i -r <paths>`.

CI runs the same script in the `linux-core` job (required for merge). The `ios` job generates the project and runs AppTests on a simulator (advisory in week 1).

## Rules

1. Stay inside the card's boundaries. Change only what the feature needs.
2. Never weaken or delete tests. Tests are XCTest, and every test method is named `func test...`.
3. Flip features.json only through `scripts/check-features.py --flip F-xxx`, which checks and runs the listed tests first. Never edit `passes` by hand.
4. Append at most 3 decision records per card to DECISIONS.md, status proposed, in this format:
   - Problem, stated without the solution.
   - Given.
   - Constraints, each with what it breaks.
   - Options, 2 to 4.
   - Decision.
   - Evidence: files and commit.
   - Reverse if.
5. Absent is not zero. Missing data is nil or an explicit absent state, shown as "--", never 0.
6. Every derived value carries a confidence.
7. No secrets or health data in the repo: no real weights, intakes, exports, tokens, keys or IPs. Tests use synthetic numbers.
8. No new dependencies, entitlements, capabilities or bundle IDs without approval. Features with needs_approval true wait for Isaac.
9. Update PROGRESS.md at the end of each card.

## Test names

features.json lists tests as `Target.Class/testMethod`, for example `StezuCoreTests.TrendWeightTests/testFirstWeighInSeedsTrend`. Core tests live in Packages/StezuCore/Tests/StezuCoreTests and app tests in App/Tests. Write the listed tests with exactly those names.

## Public repo: no personal data, ever (D-034)

This repo is public. Never commit personal data of any kind: training programs, body stats, intake, health samples, hall preferences, IPs, hostnames, tokens or server URLs. Seeds and fixtures are generic and synthetic. Isaac's own program and settings are imported on the device from a private file.
