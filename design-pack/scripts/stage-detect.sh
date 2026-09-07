#!/usr/bin/env bash
#
# stage-detect: derive the design-pack stage from what exists in the target
# repository. There is no state file; the documents are the state.
#
#   stage-detect.sh <target-dir>
#
# Prints one of:
#   A-intake    nothing exists yet: take inputs, write docs/inputs/, start cards
#   A-cards     QUESTIONS.md has cards blocking the specification without an Answer
#   B-fileset   no specs/README.md: propose the domain file set, wait for approval
#   B-write     specs/README.md exists but files in its map are missing
#   C           specs complete, no AGENTS.md
#   D           AGENTS.md exists, specs/README.md not stamped "Implementation baseline"
#   frozen      baseline stamped; changes go through the amendment regime
# followed by one line per observation that led to the verdict.
set -uo pipefail
root="${1:-.}"
cd "$root" 2>/dev/null || { echo "stage-detect: no such directory: $root" >&2; exit 2; }

say() { printf '  %s\n' "$*"; }

if [[ ! -f QUESTIONS.md && ! -d docs/inputs ]]; then
  echo "A-intake"; say "no QUESTIONS.md and no docs/inputs/"; exit 0
fi

if [[ -f QUESTIONS.md ]]; then
  # A card under ## Blocking with no Answer: line still needs the owner.
  pending="$(awk '
    /^## Blocking/ {sec="B"; next} /^## (Open|Resolved|Index)/ {sec=""; }
    sec=="B" && /^### Q-[0-9]+/ {if (cur!="" && !ans) print cur; cur=$2; ans=0; next}
    sec=="B" && /^-? *\*?\*?Answer\*?\*?:/ {ans=1}
    END {if (cur!="" && !ans) print cur}' QUESTIONS.md)"
  if [[ -n "$pending" ]]; then
    echo "A-cards"; say "blocking cards without an Answer: $(echo "$pending" | tr '\n' ' ')"; exit 0
  fi
fi

if [[ ! -f specs/README.md ]]; then
  echo "B-fileset"; say "no specs/README.md"; exit 0
fi

missing="$(grep -oE '^\| `[0-9]{2}-[a-z0-9-]+\.md`' specs/README.md | tr -d '|` ' | while read -r f; do [[ -f "specs/$f" ]] || echo "$f"; done)"
if [[ -n "$missing" ]]; then
  echo "B-write"; say "listed in the spec map but missing: $(echo "$missing" | tr '\n' ' ')"; exit 0
fi

if [[ ! -f AGENTS.md ]]; then
  echo "C"; say "specs complete, no AGENTS.md"; exit 0
fi

if ! grep -qE '^Status: *Implementation baseline' specs/README.md; then
  echo "D"; say "AGENTS.md exists; specs/README.md status: $(grep -E '^Status:' specs/README.md || echo '(none)')"; exit 0
fi

echo "frozen"; say "$(grep -E '^Version:' specs/README.md) — $(grep -E '^Status:' specs/README.md)"
