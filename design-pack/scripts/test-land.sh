#!/bin/sh
# Acceptance test for staged work and `make land` (W11.1): a rendered pack,
# two packages staged on two branches from one base, merged, landed one after the
# other; then one case per way a landing has to refuse, each proving that a
# refusal writes nothing.
#
#   scripts/test-land.sh [--keep]
#
# The pack comes from test-render.sh --render-to, so this suite and the render
# suite start from the same templates. Exits non-zero if any case behaves wrong.
set -u

here="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
keep=""
[ "${1:-}" = "--keep" ] && keep=1

pass=0
fail=0

report() {
    if [ "$1" = "ok" ]; then
        pass=$((pass + 1)); printf '  PASS  %s\n' "$2"
    else
        fail=$((fail + 1)); printf '  FAIL  %s: %s\n' "$2" "$3"
    fi
}
cleanup() {
    if [ -n "$keep" ]; then printf '\nkept: %s\n' "$work"
    else chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"; fi
}
trap cleanup EXIT

repo="$work/repo"
sh "$here/scripts/test-render.sh" --render-to "$repo" > "$work/render.out" 2>&1 \
    || { printf '  FAIL  render: %s\n' "$(tail -5 "$work/render.out")"; exit 1; }
cd "$repo" || exit 2

if command -v make >/dev/null 2>&1; then HAVE_MAKE=1; else HAVE_MAKE=""; fi
land() { if [ -n "$HAVE_MAKE" ]; then make -s land TASK="$1"; else python3 scripts/log-land.py "$1"; fi; }
gate() { python3 scripts/verify-chain.py >/dev/null && python3 scripts/check-docs.py; }
# Every file but Git's own and Python's bytecode (ignored by the pack), hashed:
# what "changed nothing" means.
snapshot() { find . \( -path ./.git -o -name __pycache__ \) -prune -o -type f -print | LC_ALL=C sort | xargs sha256sum; }
commit() { git add -A && git commit -q -m "$1"; }

printf 'staged work and make land\n'

# --- the base: FND-01 delivered, FND-02 and LDG-01 in Now -------------------------

chmod -R u+w .
python3 - <<'PYEOF'
import io, re
def rw(path, fn):
    t = io.open(path, encoding="utf-8").read()
    io.open(path, "w", encoding="utf-8", newline="\n").write(fn(t))
rw("TRACEABILITY.md", lambda t: re.sub(
    r"^\| FND-01 \| 0 \| (.*?) \| not started \| — \|$",
    r"| FND-01 | 0 | \1 | done | 2026-10-01: make verify, make clean-start |", t, flags=re.M))
rw("AGENTS.md", lambda t: t.replace(
    "None yet: no package has been delivered. The first one to reach `done` adds its line.",
    "- FND-01 — the command contract → `docs/layers/FND-01.md`"))
rw("PLAN.md", lambda t: t[:t.index("## Now")] + """## Now

### FND-02 — CI baseline

- **Outcome:** every job runs one `Makefile` target (`07` §3).
- **Lane:** tests and infrastructure
- **Branch:** wave-1/fnd-02

### LDG-01 — Notebook and entry model

- **Outcome:** the ownership constraint of `01` §2 holds in the schema.
- **Lane:** service and migrations
- **Branch:** wave-1/ldg-01

## Next

1. LDG-02 — Monthly totals (`07` §4).
""")
PYEOF
printf '# FND-01 — the command contract\n\n## What this package established\n\nEvery `make` target is real.\n\n## What a later slice must not do\n\nDo not add a gate CI runs and `make verify` does not.\n\n## Handoff\n\n### 2026-10-01\n\n- Changed: the Makefile.\n' > docs/layers/FND-01.md
commit "FND-01 delivered"

if gate > "$work/base.out" 2>&1 && [ ! -d .log/pending ]; then
    report ok "1 a pack that never stages anything passes check-docs unchanged (single-session use)" ""
else
    report no "1 single-session pack" "$(grep -E '^FAIL' "$work/base.out" | head -5)"
fi

# --- two packages staged on two branches from the same base ------------------------

git checkout -q -b wave-1/fnd-02
mkdir -p .log/pending
cat > .log/pending/FND-02.jsonl <<'EOF'
{"stream":"decisions","type":"decision-added","actor":"agent","payload":{"id":"D-NEW-1","date":"2026-10-09","title":"CI runner image","type":"implementation","decision":"CI runs on the stock Python image with PostgreSQL 16 as a service.","why":"`04` §1 requires the real engine.","alternatives":"SQLite in CI (rejected: `04` §1).","affected_specs":"none."}}
{"stream":"questions","type":"card-opened","actor":"agent","payload":{"id":"Q-NEW-1","title":"CI provider","surface":"external","source":"FND-02: the inputs name no remote","question":"Which CI service runs the pipeline?","options":["A) The remote's own CI → effect on external: one vendor.","B) A separate service → effect on external: a second account."],"recommendation":"A, because it is one fewer commitment; the runner choice is D-NEW-1.","blocks":"specification"}}
EOF
cat > docs/layers/FND-02.md <<'EOF'
# FND-02 — the CI baseline

## What this package established

One job per `make` target, on the image D-NEW-1 chose. The provider is Q-NEW-1.

## What a later slice must not do

Do not add a job that runs anything but a `make` target.

## Handoff

### 2026-10-09

- Changed: the pipeline definition.

## Landing

- traceability: done | 2026-10-09: pipeline green on the remote; D-NEW-1 recorded
- gap-add: G-NEW-1 | The CI provider is not chosen (Q-NEW-1). | The pipeline runs locally only. | Q-NEW-1 answered. | FND-02
- plan-remove
EOF
commit "FND-02: staged"

git checkout -q main
git checkout -q -b wave-1/ldg-01
mkdir -p .log/pending
cat > .log/pending/LDG-01.jsonl <<'EOF'
{"stream":"decisions","type":"decision-added","actor":"agent","payload":{"id":"D-NEW-1","date":"2026-10-09","title":"Notebook key","type":"implementation","decision":"A notebook's primary key is a UUID.","why":"Keys are never guessable (`03` §1).","alternatives":"A serial integer (rejected: enumerable).","affected_specs":"none."}}
{"stream":"decisions","type":"decision-added","actor":"agent","payload":{"id":"D-NEW-2","date":"2026-10-09","title":"Entry key","type":"implementation","decision":"An entry's key is a UUID as well, for the reason D-NEW-1 gives.","why":"One key type across the schema.","alternatives":"A serial integer per notebook (rejected: two key types).","affected_specs":"none."}}
EOF
cat > docs/layers/LDG-01.md <<'EOF'
# LDG-01 — the notebook and entry model

## What this package established

`notebooks` and `entries`, both keyed by UUID (D-NEW-1, D-NEW-2).

## What a later slice must not do

Do not read an entry without its notebook's keeper.

## Handoff

### 2026-10-09

- Changed: two tables and their migration.

## Landing

- traceability: in progress | 2026-10-09: make test (NotebookSchemaTest) passed
- gap-add: G-NEW-1 | Entries have no index on their date. | Month queries scan. | A measurement. | LDG-02
EOF
commit "LDG-01: staged"

if python3 scripts/check-docs.py --only pending > "$work/staged.out" 2>&1; then
    report ok "2 staged work on a branch passes the \`pending\` rule" ""
else
    report no "2 staged form" "$(grep -E '^FAIL' "$work/staged.out" | head -5)"
fi

git checkout -q main
if git merge -q --no-edit wave-1/fnd-02 > "$work/m1.out" 2>&1 \
   && git merge -q --no-edit wave-1/ldg-01 > "$work/m2.out" 2>&1; then
    report ok "3 both branches merge into one base without a conflict: neither touched the log or a shared document" ""
else
    report no "3 merge" "$(cat "$work/m1.out" "$work/m2.out")"
fi

# --- landed one after the other ----------------------------------------------------

if land FND-02 > "$work/l1.out" 2>&1 && land LDG-01 > "$work/l2.out" 2>&1; then
    report ok "4 make land lands both packages, one after the other" ""
else
    report no "4 land" "$(cat "$work/l1.out" "$work/l2.out")"
fi

if python3 scripts/verify-chain.py > "$work/vc.out" 2>&1; then
    report ok "5 verify-chain passes: one chain, not two forked from the same record" ""
else
    report no "5 verify-chain" "$(cat "$work/vc.out")"
fi

ids="$(grep -oE '^- D-[0-9]{3}' DECISIONS.md | sed 's/^- //' | tr '\n' ' ')"
if [ "$ids" = "D-001 D-002 D-003 D-004 D-005 D-006 D-007 D-008 " ] \
   && grep -q '^- Q-003 — CI provider' QUESTIONS.md; then
    report ok "6 IDs are contiguous across the two packages: D-006 for FND-02, D-007 and D-008 for LDG-01, Q-003" ""
else
    report no "6 contiguous IDs" "decisions: $ids"
fi

if grep -q 'image D-006 chose. The provider is Q-003' docs/layers/FND-02.md \
   && grep -q '(D-007, D-008)' docs/layers/LDG-01.md \
   && ! grep -q 'NEW-' docs/layers/FND-02.md docs/layers/LDG-01.md \
   && grep -q 'for the reason D-007 gives' DECISIONS.md \
   && grep -q 'the runner choice is D-006' QUESTIONS.md; then
    report ok "7 each layer note cites its own real IDs, and so do the events that referred to each other" ""
else
    report no "7 placeholders rewritten" "$(grep -n 'D-0\|Q-0\|NEW' docs/layers/FND-02.md docs/layers/LDG-01.md)"
fi

if [ ! -e .log/pending/FND-02.jsonl ] && [ ! -e .log/pending/LDG-01.jsonl ] \
   && ! grep -q '^## Landing' docs/layers/FND-02.md docs/layers/LDG-01.md \
   && grep -q '^| FND-02 | 0 | .* | done | 2026-10-09: pipeline green on the remote; D-006 recorded |$' TRACEABILITY.md \
   && grep -q '^| LDG-01 | 1 | .* | in progress | ' TRACEABILITY.md \
   && grep -q '^| G-002 | The CI provider is not chosen (Q-003)' GAPS.md \
   && grep -q '^| G-003 | Entries have no index on their date' GAPS.md \
   && ! grep -q '^### FND-02' PLAN.md && grep -q '^### LDG-01' PLAN.md \
   && grep -q '^- FND-02 — the CI baseline → `docs/layers/FND-02.md`$' AGENTS.md \
   && ! grep -q '^- LDG-01' AGENTS.md; then
    report ok "8 the landing lines are applied and removed: rows, gaps, the plan item, and the index line of the package that landed done" ""
else
    report no "8 documents" "$(git status --short | head; grep -n 'FND-02\|G-00' TRACEABILITY.md GAPS.md AGENTS.md PLAN.md | head)"
fi

if gate > "$work/after.out" 2>&1; then
    report ok "9 the whole gate passes on the landed pack" ""
else
    report no "9 gate after landing" "$(grep -E '^FAIL' "$work/after.out" | head -5)"
fi
commit "land FND-02, LDG-01"

# --- a refusal changes nothing ----------------------------------------------------

mkdir -p .log/pending
cat > .log/pending/LDG-02.jsonl <<'EOF'
{"stream":"decisions","type":"decision-added","actor":"agent","payload":{"id":"D-NEW-1","date":"2026-10-09","title":"Totals cache","type":"implementation","decision":"No cache.","why":"Totals are derived at read time.","alternatives":"A cache.","affected_specs":"none."}}
{"stream":"decisions","type":"decision-added","actor":"agent","payload":{"id":"D-NEW-2","date":"2026-10-09","title":"Totals rounding","type":"implementation","decision":"Banker's rounding.","why":"As `01` §9 says.","alternatives":"Half up.","affected_specs":"none."}}
EOF
printf '# LDG-02 — monthly totals\n\n## What this package established\n\nD-NEW-1.\n\n## What a later slice must not do\n\nNothing yet.\n\n## Handoff\n\n### 2026-10-09\n\n- Started.\n\n## Landing\n\n- traceability: in progress | 2026-10-09: begun\n' > docs/layers/LDG-02.md
snapshot > "$work/before"
if land LDG-02 > "$work/r1.out" 2>&1; then
    report no "10 a dead citation" "land exited 0"
elif grep -q 'staged line 2: this decision cites a section that does not exist' "$work/r1.out" \
     && snapshot | cmp -s - "$work/before"; then
    report ok "10 a staged event log-append would refuse (a dead citation) makes land exit non-zero, and nothing changed, byte for byte" ""
else
    report no "10 dead citation" "$(cat "$work/r1.out"; snapshot | diff "$work/before" - | head -5)"
fi

sed -i '2s/"decision-added"/"decision-invented"/' .log/pending/LDG-02.jsonl
snapshot > "$work/before"
if land LDG-02 > "$work/r2.out" 2>&1; then
    report no "11 an unknown event type" "land exited 0"
elif grep -q "line 2: unknown decisions event 'decision-invented'" "$work/r2.out" \
     && snapshot | cmp -s - "$work/before"; then
    report ok "11 an unknown event type makes land exit non-zero, and nothing changed" ""
else
    report no "11 unknown type" "$(cat "$work/r2.out")"
fi

# --- the pending rule ----------------------------------------------------------------

printf '{"stream":"decisions","type":"decision-added","actor":"agent","payload":{"id":"D-009","date":"2026-10-09","title":"Totals cache","type":"implementation","decision":"No cache.","why":"Derived at read time.","alternatives":"A cache.","affected_specs":"none."}}\n' > .log/pending/LDG-02.jsonl
if python3 scripts/check-docs.py --only pending > "$work/p1.out" 2>&1; then
    report no "12 a real ID in a staging file" "check-docs passed"
elif grep -q 'FAIL pending .*\.log/pending/LDG-02.jsonl:1: decision-added assigns the real ID D-009' "$work/p1.out"; then
    report ok "12 a staging file carrying a real D-NNN fails \`pending\`, naming the line" ""
else
    report no "12 real ID" "$(grep FAIL "$work/p1.out")"
fi
rm -f .log/pending/LDG-02.jsonl docs/layers/LDG-02.md

printf '{"stream":"decisions","type":"decision-added","actor":"agent","payload":{"id":"D-NEW-1","date":"2026-10-09","title":"Late","type":"implementation","decision":"x.","why":"y.","alternatives":"z.","affected_specs":"none."}}\n' > .log/pending/FND-02.jsonl
if python3 scripts/check-docs.py --only pending > "$work/p2.out" 2>&1; then
    report no "13 a done package with a staging file" "check-docs passed"
elif grep -q 'FAIL pending .*FND-02.jsonl: FND-02 is `done` in TRACEABILITY.md and still has staged work' "$work/p2.out"; then
    report ok "13 a \`done\` package with a leftover staging file fails \`pending\`" ""
else
    report no "13 leftover staging" "$(grep FAIL "$work/p2.out")"
fi
rm -f .log/pending/FND-02.jsonl

printf '\n## Landing\n\n- plan-remove\n' >> docs/layers/FND-02.md
if python3 scripts/check-docs.py --only pending > "$work/p3.out" 2>&1; then
    report no "13b a done package with a Landing section" "check-docs passed"
elif grep -q 'FAIL pending .*docs/layers/FND-02.md: FND-02 is `done` and its note still carries `## Landing`' "$work/p3.out"; then
    report ok "13b a \`done\` package whose note still carries \`## Landing\` fails \`pending\`" ""
else
    report no "13b leftover landing" "$(grep FAIL "$work/p3.out")"
fi
git checkout -q -- docs/layers/FND-02.md

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
