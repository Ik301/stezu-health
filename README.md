# Stezu Health

A minimal iPhone health app for photo meal logging, gym sets, weigh-ins and Apple Health. It is built largely by AI agents working overnight behind deterministic gates (build, tests, a feature ledger and a diff budget), and a human reviews and defends the decisions afterwards. SPEC.md describes the product, DESIGN.md the visual tokens, AGENTS.md the rules the agents follow, and DECISIONS.md every decision along with what would reverse it.

## Build on your Mac

You need Xcode, XcodeGen (`brew install xcodegen`) and an Apple ID; a free Personal Team works.

    git clone https://github.com/Ik301/stezu-health.git && cd stezu-health
    scripts/set-team.sh          # once per clone; or scripts/set-team.sh <TEAM_ID>
    xcodegen generate            # after any pull that changes project.yml or adds files
    open StezuHealth.xcodeproj   # pick your iPhone, then Cmd+R

`scripts/set-team.sh` finds your Team ID on your Apple Development certificate (or takes it as
an argument), writes it to `Config/Local.xcconfig`, which git ignores, and runs `xcodegen
generate`. `Config/Signing.xcconfig` includes that file for the app and its Live Activity
extension, so a regenerate no longer resets signing and you never pick the team in Xcode again.
If the script cannot find a team, it prints where to look it up in Xcode.
