#!/usr/bin/env bash
# Install Oyloo pre-commit hook (and any future hooks) for this repo.
# Sets git core.hooksPath to scripts/git-hooks/ so all hooks there activate.
#
# Run once per clone, on each Mac. Idempotent.

set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)/git-hooks"

if [[ ! -d "$HOOKS_DIR" ]]; then
    echo "ERROR: hooks dir not found at $HOOKS_DIR" >&2
    exit 1
fi

if ! REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
    echo "ERROR: not in a git repo (run from inside the repo root)" >&2
    exit 1
fi

# Path relative to repo root
REL_HOOKS="${HOOKS_DIR#$REPO_ROOT/}"

git config core.hooksPath "$REL_HOOKS"
chmod +x "$HOOKS_DIR"/* 2>/dev/null || true

echo "✓ git core.hooksPath = $REL_HOOKS"
echo
echo "Active hooks:"
ls -la "$HOOKS_DIR"
echo
echo "Verify the blocklist exists:"
echo "    ls -la \${OYLOO_BLOCKLIST:-\$HOME/.config/oyloo/private-terms.txt}"
echo
echo "Test by staging content with a known-blocked term and 'git commit'."
