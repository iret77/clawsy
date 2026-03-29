# Agent Instructions

These rules apply to all AI agents working on this repository.

## Git Workflow
- **Never push directly to `main`.** All changes go through feature branches and pull requests.
- **Branch naming:** `feat/`, `fix/`, `refactor/`, `docs/`, `chore/` prefixes.
- **Conventional commits:** `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`, `release:`, `dev:`.
- **Never force-push** to any shared branch.
- **Never commit secrets** (.env, API keys, tokens, credentials).
- **Never skip hooks** (`--no-verify`).

## Pull Requests
- Keep PR titles short (<70 chars), use conventional prefix.
- One logical change per PR.
- Ensure CI passes before requesting merge.

## Pre-push Hook
A `.hooks/pre-push` hook blocks direct pushes to `main`/`master`. Override only when explicitly instructed:
```bash
ALLOW_PUSH_TO_MAIN=1 git push origin main
```

## Clawsy-specific Rules
- **No local builds.** Swift is NOT available on the dev machine. Push to CI and watch the build.
- **Never ask the user to build, run `./build.sh`, or open Xcode.**
- **Localization:** All user-facing strings use `NSLocalizedString` with `bundle: .clawsy`. Strings go in `Sources/ClawsyShared/Resources/{en,de,fr,es}.lproj/Localizable.strings`.
- **Bundle resolution:** `.clawsy` resolves to `Clawsy_ClawsyShared.bundle` — localization strings must be in ClawsyShared/Resources, NOT ClawsyMac/Resources.
- **UI quality bar:** All UI must pass Apple HIG standards — native macOS feel, never developer UI.

## Release Process
- **Dev/test changes:** Feature branch → PR → merge to main → CI builds artifact
- **Stable release:** Tag `vX.Y.Z` on main → CI creates GitHub Release with `.zip`
- Never tag without explicit user instruction.
