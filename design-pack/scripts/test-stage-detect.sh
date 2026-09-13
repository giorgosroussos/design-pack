#!/bin/sh
# Acceptance test for stage-detect.sh: walk a target through every state the
# documents can be in and assert the verdict at each step, including the two the
# dry run found wrong (after intake, before any card; after the last answer,
# before the file set) and the one that is right by design (a Blocking card
# opened during Stage B reports A-cards).
#
#   scripts/test-stage-detect.sh [--keep]
set -u

here="$(cd "$(dirname "$0")/.." && pwd)"
tpl="$here/templates"
work="$(mktemp -d)"
keep=""
[ "${1:-}" = "--keep" ] && keep=1
pass=0; fail=0
report() { if [ "$1" = "ok" ]; then pass=$((pass + 1)); printf '  PASS  %s\n' "$2"; else fail=$((fail + 1)); printf '  FAIL  %s: %s\n' "$2" "$3"; fi; }
cleanup() { if [ -n "$keep" ]; then printf '\nkept: %s\n' "$work"; else rm -rf "$work"; fi; }
trap cleanup EXIT

repo="$work/repo"; mkdir -p "$repo/scripts"; cd "$repo" || exit 2
for f in eventlog.py log-append.py rebuild-questions.py; do cp "$tpl/scripts/$f" "scripts/$f"; done

verdict() { bash "$here/scripts/stage-detect.sh" . | head -1; }
expect() {  # expect <label> <state>
    got="$(verdict)"
    if [ "$got" = "$2" ]; then report ok "$1 → $2" ""; else report no "$1" "stage-detect said '$got', expected '$2'"; fi
}
card() {  # card <id> <blocks-in-recommendation>
    python3 scripts/log-append.py --quiet --stream questions --type card-opened --payload-file - <<EOF
{"id":"$1","title":"Card $1","surface":"data","source":"the brief","question":"Which?",
 "options":["A) one → effect on data: x.","B) two → effect on data: y."],
 "recommendation":"A, because it is simpler.","blocks":"specification"}
EOF
}
rebuild() { python3 scripts/rebuild-questions.py --quiet; }

printf 'stage-detect acceptance\n'

expect "1 empty directory" "A-intake"

mkdir -p docs/inputs .log; printf '# brief\n' > docs/inputs/brief-2026-09-13.md; : > .log/events.jsonl; rebuild
expect "2 inputs saved, QUESTIONS.md rendered empty (Round A0 stop)" "A-extract"

card Q-001; card Q-002; rebuild
expect "3 two Blocking cards, none answered (batch presented)" "A-cards"

python3 scripts/log-append.py --quiet --stream questions --type card-answered --set id=Q-001 --set answer=A --set date=2026-09-13; rebuild
expect "4 one answered, one still Blocking" "A-cards"

python3 scripts/log-append.py --quiet --stream questions --type card-deferred --set id=Q-002 --set blocks="Phase 2"; rebuild
expect "5 the other deferred by the owner (Open): Stage A is over" "B-fileset"

mkdir -p specs
printf '# Specs\n\nVersion: 0.1-draft  \nStatus: Draft, not yet an implementation baseline  \n\n## Specification map\n\n| File | Purpose |\n| --- | --- |\n| `01-scope.md` | Scope |\n| `02-arch.md` | Architecture |\n' > specs/README.md
expect "6 spec map written, files missing" "B-write"

printf '# Scope\n' > specs/01-scope.md
expect "6b one of two spec files still missing" "B-write"

card Q-003; rebuild
expect "7 a Blocking card raised during Stage B (by design: answer first)" "A-cards"
python3 scripts/log-append.py --quiet --stream questions --type card-answered --set id=Q-003 --set answer=B --set date=2026-09-13; rebuild

printf '# Arch\n' > specs/02-arch.md
expect "8 every mapped spec file exists, no AGENTS.md" "C"

printf '# AGENTS\n' > AGENTS.md
expect "9 AGENTS.md exists, spec map still Draft" "D"

sed -i 's/^Status: Draft.*/Status: Implementation baseline, 2026-09-13  /' specs/README.md
expect "10 baseline stamped" "frozen"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
