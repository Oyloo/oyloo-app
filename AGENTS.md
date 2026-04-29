# Agent Instructions — oyloo-app

This file is the canonical agent contract. `CLAUDE.md` and `GEMINI.md` are
symlinks to this file.

## Repo policy: PUBLIC-target

This repo is currently private but designed to ship as PUBLIC. Treat every
commit as if it will be visible on the open internet tomorrow.

## Private-terms protection — required before any commit

A pre-commit hook (`scripts/git-hooks/pre-commit`) refuses commits that add
content matching patterns in `~/.config/oyloo/private-terms.txt`. The hook
is **fail-closed**: if the blocklist file is missing, all commits are
refused.

Setup on a fresh machine:

```bash
bash scripts/install-hooks.sh           # sets core.hooksPath
mkdir -p ~/.config/oyloo
chmod 700 ~/.config/oyloo
# Transfer the canonical blocklist via 1Password / scp from another Mac.
chmod 600 ~/.config/oyloo/private-terms.txt
```

The blocklist file is the single source of truth listing private terms.
It lives only in `~/.config/oyloo/` on each developer machine — never in
this repo, never in any other repo, never on a shared system.

## iOS-specific notes

- App Group IDs, bundle identifiers, Apple Team IDs visible in `project.yml`,
  `*.entitlements`, and Swift constants are user-facing identifiers. Treat
  them as semi-public (Apple ships them in the App Store binary anyway) —
  but never combine with private deployment context.
- UDIDs, provisioning profiles, push tokens — never in the repo. Use
  placeholders in docs (`<UDID>`, `<TOKEN>`).
- Signing/codesign cert serials are sensitive. Never commit.

## What MUST stay out of this repo

See blocklist categories. In short: organizational refs, identities,
infrastructure, internal codenames, sibling private repos, internal
operational phrases.

## What is allowed

- Public framework / SDK names (SwiftUI, UIKit, FoundationModels).
- Apple-public team-level identifiers (only in build configs where Apple
  themselves expose them).
- Generic vendor / product references in capture-extension code.

## Bypass (rare, audited)

```bash
git commit --no-verify
```

Document the reason in the commit message. Bypasses are visible in git log.

## When in doubt

Don't commit. Move the work to a private repo and upstream the
scrubbed-generic version later.
