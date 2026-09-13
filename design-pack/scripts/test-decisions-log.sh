#!/bin/sh
# Acceptance test for the decisions log and its projection: append, rebuild,
# verify, and the three ways the pair can be attacked (edit a log line, edit the
# projection, append onto a broken chain). Runs in a throwaway directory; needs
# no git, because none of this depends on git.
#
#   scripts/test-decisions-log.sh [--keep]
#
# Exits non-zero if any case behaves wrong.
set -u

here="$(cd "$(dirname "$0")/.." && pwd)"
tpl="$here/templates"
work="$(mktemp -d)"
keep=""
[ "${1:-}" = "--keep" ] && keep=1

pass=0
fail=0

report() {
    if [ "$1" = "ok" ]; then
        pass=$((pass + 1))
        printf '  PASS  %s\n' "$2"
    else
        fail=$((fail + 1))
        printf '  FAIL  %s: %s\n' "$2" "$3"
    fi
}

cleanup() {
    if [ -n "$keep" ]; then printf '\nkept: %s\n' "$work"; else rm -rf "$work"; fi
}
trap cleanup EXIT

repo="$work/repo"
mkdir -p "$repo/scripts"
cd "$repo" || exit 2
for f in eventlog.py log-append.py verify-chain.py rebuild-decisions.py check-docs.py; do
    cp "$tpl/scripts/$f" "scripts/$f"
done

# The two check-docs rules under test, run in a fresh process each time so the
# module-level failure list starts empty.
cat > probe.py <<'PROBEEOF'
import importlib.util
import os
import sys

spec = importlib.util.spec_from_file_location("checkdocs", "scripts/check-docs.py")
checkdocs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checkdocs)
root = os.path.abspath(".")
checkdocs.check_decisions(root)
checkdocs.check_log(root)
for line in checkdocs.failures:
    print(line)
sys.exit(1 if checkdocs.failures else 0)
PROBEEOF

append() { python3 scripts/log-append.py --quiet "$@"; }
seqs() { python3 -c "import json,sys;print(','.join(str(json.loads(l)['seq']) for l in open('.log/events.jsonl')))"; }

printf 'decisions log acceptance\n'

# --- 1. two decision-added events, rebuilt ------------------------------------

append --type decision-added --set id=D-001 --set date=2026-09-04 \
    --set title="Repository documentation regime" --set type=implementation \
    --set decision="AGENTS.md at the root is the single entry point." \
    --set why="A fresh session must find one file and be unable to miss the state." \
    --set alternatives="Living documents under docs/ (rejected: discoverability)." \
    --set affected_specs="none." || report no "1 append D-001" "log-append failed"
append --type decision-added --set id=D-002 --set date=2026-09-04 \
    --set title="API base path" --set type=implementation \
    --set decision="The API base path is /api/v1." \
    --set why="Versioning from the first endpoint costs nothing later." \
    --set alternatives="Unversioned paths (rejected: no way out)." \
    --set affected_specs="09 §1." || report no "1 append D-002" "log-append failed"

python3 scripts/rebuild-decisions.py --quiet

if grep -q '^## D-001 (2026-09-04) — Repository documentation regime$' DECISIONS.md &&
   grep -q '^## D-002 (2026-09-04) — API base path$' DECISIONS.md &&
   grep -q '^- D-001 — Repository documentation regime — implementation$' DECISIONS.md; then
    report ok "1 rebuild: both records and their index lines are in the projection" ""
else
    report no "1 rebuild" "a record or an index line is missing"
fi

if python3 probe.py > "$work/probe1.out" 2>&1; then
    report ok "1 the projection passes the decisions rule and projection-fresh" ""
else
    report no "1 check rules" "$(cat "$work/probe1.out")"
fi

# determinism: the renderer is a pure function of the log or projection-fresh lies
python3 scripts/rebuild-decisions.py --stdout > "$work/r1.txt"
python3 scripts/rebuild-decisions.py --stdout > "$work/r2.txt"
if cmp -s "$work/r1.txt" "$work/r2.txt" && cmp -s "$work/r1.txt" DECISIONS.md; then
    report ok "1b the rebuild is byte-identical across runs and equals the file" ""
else
    report no "1b determinism" "two renderings of one log differ"
fi

# --- 2. supersession ----------------------------------------------------------

append --type decision-superseded --set id=D-001 --set by=D-002
python3 scripts/rebuild-decisions.py --quiet

if python3 - <<'EOF'
import re
text = open("DECISIONS.md", encoding="utf-8").read()
entry = re.search(r"^## D-001 .*?(?=^## |\Z)", text, re.M | re.S).group(0)
assert "Status: superseded by D-002" in entry, "no status line on D-001"
assert "Decision: AGENTS.md at the root is the single entry point." in entry, "the text was collapsed"
assert "superseded by D-002" in re.search(r"^- D-001 .*$", text, re.M).group(0), "index not marked"
EOF
then
    report ok "2 supersession: D-001 carries the status line and keeps its text" ""
else
    report no "2 supersession" "the projection did not render the supersession"
fi

if [ "$(seqs)" = "1,2,3" ]; then
    report ok "2b the log holds three contiguous records" ""
else
    report no "2b sequence" "seqs are $(seqs), expected 1,2,3"
fi

if python3 scripts/verify-chain.py --quiet && python3 probe.py > "$work/probe2.out" 2>&1; then
    report ok "2c chain-intact and projection-fresh still pass" ""
else
    report no "2c chain and projection" "$(cat "$work/probe2.out" 2>/dev/null)"
fi

cp .log/events.jsonl "$work/good.jsonl"

# --- 3. one character changed inside an existing log line ---------------------

python3 - <<'EOF'
path = ".log/events.jsonl"
lines = open(path, encoding="utf-8").read().splitlines()
lines[1] = lines[1].replace("/api/v1", "/api/v2")
assert "/api/v2" in lines[1], "the test could not tamper with line 2"
open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
EOF

if python3 scripts/verify-chain.py > "$work/chain3.out" 2>&1; then
    report no "3 verify-chain on a tampered record" "it reported the chain intact"
elif grep -q 'line 2' "$work/chain3.out"; then
    report ok "3 verify-chain fails and names line 2" ""
else
    report no "3 verify-chain naming" "$(cat "$work/chain3.out")"
fi

if python3 probe.py > "$work/probe3.out" 2>&1; then
    report no "3b chain-intact on a tampered record" "check-docs reported no failure"
elif grep -q 'chain-intact' "$work/probe3.out" && grep -q ':2' "$work/probe3.out"; then
    report ok "3b chain-intact fails, naming the record" ""
else
    report no "3b chain-intact naming" "$(cat "$work/probe3.out")"
fi

# --- 5. log-append refuses to build on a broken chain -------------------------
# (before restoring, since this is the same tampered state)

if append --type decision-added --set id=D-003 --set date=2026-09-04 --set title="Third" \
        --set type=implementation --set decision="x." --set why="y." \
        --set alternatives="z." --set affected_specs="none." > "$work/append5.out" 2>&1; then
    report no "5 append onto a broken chain" "it appended anyway"
else
    if [ "$(wc -l < .log/events.jsonl)" = "3" ] && grep -qi 'broken chain' "$work/append5.out"; then
        report ok "5 log-append refuses to append onto a broken chain" ""
    else
        report no "5 append refusal" "wrong reason or the log grew: $(cat "$work/append5.out")"
    fi
fi

cp "$work/good.jsonl" .log/events.jsonl
python3 scripts/verify-chain.py --quiet || report no "3c restore" "the good log does not verify"

# --- 4. a hand edit of the projection ----------------------------------------

printf '\nA line somebody typed straight into the projection.\n' >> DECISIONS.md

if python3 probe.py > "$work/probe4.out" 2>&1; then
    report no "4 projection-fresh on a hand-edited file" "check-docs reported no failure"
elif grep -q 'projection-fresh' "$work/probe4.out"; then
    report ok "4 projection-fresh fails on a hand edit" ""
else
    report no "4 projection-fresh" "$(cat "$work/probe4.out")"
fi

if python3 scripts/rebuild-decisions.py --quiet && python3 probe.py > "$work/probe4b.out" 2>&1; then
    report ok "4b a rebuild restores the projection and the check passes again" ""
else
    report no "4b rebuild after a hand edit" "$(cat "$work/probe4b.out" 2>/dev/null)"
fi

# --- 6. events the log refuses because no projection could fold them ---------
# The log holds D-001, D-002 and a supersession; the next decision is D-003.

if append --type decision-added --set id=D-004 --set date=2026-09-04 --set title="Skips ahead" \
        --set type=implementation --set decision="x." --set why="y." \
        --set alternatives="z." --set affected_specs="none." > "$work/gap.out" 2>&1; then
    report no "6 a decision whose ID skips ahead" "D-004 was accepted while D-003 is next"
elif grep -q 'breaks the sequence' "$work/gap.out"; then
    report ok "6 a decision whose ID skips ahead is refused (D-004 when D-003 is next)" ""
else
    report no "6 gap refusal reason" "$(cat "$work/gap.out")"
fi

if append --type adr-approval-changed --set id=D-002 --set approval=granted \
        --set approval_date=2026-09-04 > "$work/adr.out" 2>&1; then
    report no "6b an approval on a non-ADR" "it attached to an implementation decision"
elif grep -q 'not adr' "$work/adr.out"; then
    report ok "6b an owner approval aimed at an implementation decision is refused" ""
else
    report no "6b approval refusal reason" "$(cat "$work/adr.out")"
fi

if [ "$(seqs)" = "1,2,3" ]; then
    report ok "6c the log is unchanged by the refusals" ""
else
    report no "6c refusal side effects" "seqs are $(seqs)"
fi

# --check must decide before --stdout: printing is not checking
printf '\ndrift\n' >> DECISIONS.md
if python3 scripts/rebuild-decisions.py --check --stdout > /dev/null 2>&1; then
    report no "6d --check --stdout on a drifted file" "exited 0"
else
    report ok "6d --check wins over --stdout: a drifted file still exits 1" ""
fi
python3 scripts/rebuild-decisions.py --quiet

# --- 7. a decision citing a missing section of an existing spec is refused ------

mkdir -p specs
printf '# Scope\n\n## 1. Purpose\n\nText.\n' > specs/01-scope.md
if append --type decision-added --set id=D-003 --set date=2026-09-04 --set title="Dead citation" \
        --set type=implementation --set decision="Cites \`01\` §7, which does not exist." --set why="y." \
        --set alternatives="z." --set affected_specs="\`01\` §7." > "$work/cite.out" 2>&1; then
    report no "7 a decision citing a missing section" "it was appended; the failure is now permanent"
elif grep -q 'does not resolve' "$work/cite.out" && [ "$(seqs)" = "1,2,3" ]; then
    report ok "7 a decision citing a section missing from an existing spec is refused, nothing appended" ""
else
    report no "7 dead citation refusal" "$(cat "$work/cite.out")"
fi
if append --type decision-added --set id=D-003 --set date=2026-09-04 --set title="Future citation" \
        --set type=implementation --set decision="Cites \`05\` §2, a spec not written yet." --set why="y." \
        --set alternatives="z." --set affected_specs="none." > "$work/cite2.out" 2>&1 && [ "$(seqs)" = "1,2,3,4" ]; then
    report ok "7b a citation into a spec not written yet is accepted; the gate checks it later" ""
else
    report no "7b future citation" "$(cat "$work/cite2.out")"
fi
python3 scripts/rebuild-decisions.py --quiet
rm -rf specs

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
