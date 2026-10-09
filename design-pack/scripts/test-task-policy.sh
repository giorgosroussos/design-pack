#!/bin/sh
# Acceptance test for the `task-policy` rule and the `--task` reader of
# check-docs.py: a small fixture pack whose plan, specs, cards and red lines are
# just enough to derive the two derived characteristics, then one case per way
# the data and the policy can disagree.
#
#   scripts/test-task-policy.sh [--keep]
#
# The rule-level suite for every other rule is test-check-docs.sh; the whole gate
# over the shipped templates is test-render.sh. Exits non-zero if any case
# behaves wrong.
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
        pass=$((pass + 1)); printf '  PASS  %s\n' "$2"
    else
        fail=$((fail + 1)); printf '  FAIL  %s: %s\n' "$2" "$3"
    fi
}
cleanup() { if [ -n "$keep" ]; then printf '\nkept: %s\n' "$work"; else rm -rf "$work"; fi; }
trap cleanup EXIT

repo="$work/repo"
mkdir -p "$repo/scripts" "$repo/specs"
cd "$repo" || exit 2
cp "$tpl/scripts/check-docs.py" scripts/check-docs.py

# probe: load check-docs.py, run the rule, print its FAIL lines, exit 1 if any.
probe() {
    python3 - "$1" <<'PROBEEOF'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("checkdocs", "scripts/check-docs.py")
cd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cd)
root = os.path.abspath(".")
cards, resolved, superseded = cd.parse_cards(root)
exec(sys.argv[1])
for line in cd.failures:
    print(line)
sys.exit(1 if cd.failures else 0)
PROBEEOF
}
rule() { probe 'cd.check_task_policy(root, cards)'; }

# --- the fixture ---------------------------------------------------------------
# `01` §2 carries a [Q-001] statement and is cited by a register bullet under
# Security, so it resolves to the security surface and nothing else does. A red
# line cites the same section. PKG-01 cites `01` §2, PKG-02 cites `01` §1.

fixture() {
    cat > specs/01-scope.md <<'EOF'
# Scope

## 1. Purpose

The tool records entries and totals them. Nothing here fixes a surface.

## 2. Access

- A notebook MUST be readable by its keeper only. [Q-001]
EOF

    cat > specs/02-decision-register.md <<'EOF'
# Locked Decision Register

## 1. Data

No locked decision on this surface.

## 2. Security

- A notebook is private to its keeper (`01` §2). [Q-001]

## 6. Change control

A proposed change requires an ADR. [D-001]
EOF

    cat > specs/03-implementation-plan.md <<'EOF'
# Implementation Plan

## 3. Phase 0 — Foundations

### Work packages

`PKG-01` Keeper access

- Enforce the ownership rule of `01` §2 in one place.
- Surfaces: security
- Touches red line: yes
- Contract change: no
- File surface: app/access, tests/access
- Lane: service

`PKG-02` Totals

- Derive the monthly total as `01` §1 describes.
- Surfaces: —
- Touches red line: no
- Contract change: yes
- File surface: app/totals, tests/totals
- Lane: service

`PKG-03` Keeper access on one line — `01` §2.

- Surfaces: security
- Touches red line: yes
- Contract change: no
- File surface: docs
- Lane: tests and infrastructure

## 5. Safe parallelization

Suggested maximum lanes:

- service
- tests and infrastructure
EOF

    cat > AGENTS.md <<'EOF'
# AGENTS.md — Fixture

## Non-negotiable constraints

- **One keeper per notebook.** A notebook is readable by its keeper only (`01` §2).

## Prompt selection

The mechanical gates are the floor for every task.

| Prompt | Run when |
| --- | --- |
| 1 — Implement | Always, unless an orchestrator runs the package. |
| 1o — Implement (orchestrated) | Under an orchestrator, in place of prompt 1; prompts 2 and 3 are unchanged. |
| 3 — Resolve questions | Before the package, iff an open card in QUESTIONS.md has `Blocks:` = this package. |
| 2 — Review | After implementation, iff `Surfaces` includes `security` or `data`, or `Touches red line` is `yes`, or `Contract change` is `yes`. Otherwise skip: the executable acceptance criteria and `make check-docs` already cover correctness. |

## Living documents

Nothing here.
EOF

    cat > QUESTIONS.md <<'EOF'
# QUESTIONS

## Index

- Q-001 — Notebook sharing — security — Resolved
- Q-002 — Entry retention — data — Open

## Blocking

None. Phase 0 can proceed.

## Open

### Q-002 — Entry retention
- Surface: data
- Source: absent from the inputs
- Question: Are entries ever deleted?
- Options:
  - A) Never → effect on data: unbounded growth.
  - B) Purge after N years → effect on data: a retention period.
- Recommendation: A, because the input is silent.
- Blocks: PKG-02

## Resolved

### Q-001 — Notebook sharing
- Surface: security
- Source: the fixture
- Question: Is a notebook ever readable by anyone but its keeper?
- Options:
  - A) No → effect on security: one principal.
  - B) Read-only sharing → effect on security: a grant table.
- Recommendation: A, because the input says so.
- Blocks: specification
- Answer: A (2026-09-14; recommendation accepted)
EOF
}

printf 'task-policy acceptance\n'

# --- 1 and 2: the derived values the fixture states are the ones it derives ----

fixture
if rule > "$work/1.out" 2>&1; then
    report ok "1+2 a package citing a security-surfaced section states \`Surfaces: security\`, one citing none states the dash, and the rule passes" ""
    report ok "2b a package written as a single line, citing on its title line, derives from that line" ""
else
    report no "1+2 baseline" "$(cat "$work/1.out")"
fi

# --- 3: a stored Surfaces that disagrees with the cited sections ---------------

sed -i 's/^- Surfaces: security$/- Surfaces: data/' specs/03-implementation-plan.md
if rule > "$work/3.out" 2>&1; then
    report no "3 hand-edited Surfaces" "no failure reported"
elif grep -q 'FAIL task-policy' "$work/3.out" && grep -q 'PKG-01 states `Surfaces: data`' "$work/3.out" \
     && grep -q 'derives `security`' "$work/3.out"; then
    report ok "3 a hand-edited \`Surfaces\` fails, naming the package, both values and the sections it cites" ""
else
    report no "3 Surfaces drift" "$(cat "$work/3.out")"
fi

# --- 4: a red line moves onto a package that says it touches none --------------

fixture
sed -i 's|^- \*\*One keeper per notebook.*$|&\n- **Totals are derived.** A total is computed at read time (`01` §1).|' AGENTS.md
if rule > "$work/4.out" 2>&1; then
    report no "4 red line over PKG-02" "no failure reported"
elif grep -q 'PKG-02 states `Touches red line: no`' "$work/4.out" && grep -q 'a red line cites' "$work/4.out"; then
    report ok "4 a red line that cites a section a package cites fails that package's \`Touches red line: no\`" ""
else
    report no "4 red line" "$(cat "$work/4.out")"
fi

# --- 5: the table may name only the three real prompts and real characteristics --

fixture
python3 - <<'PYEOF'
import io
t = io.open("AGENTS.md", encoding="utf-8").read()
t = t.replace("\n## Living documents", "| 4 — Deploy | Whenever it feels right. |\n\n## Living documents")
io.open("AGENTS.md", "w", encoding="utf-8", newline="\n").write(t)
PYEOF
if rule > "$work/5a.out" 2>&1; then
    report no "5a a fourth prompt" "no failure reported"
elif grep -q 'names prompt 4, which does not exist' "$work/5a.out"; then
    report ok "5a a table row for a prompt that does not exist fails" ""
else
    report no "5a fourth prompt" "$(cat "$work/5a.out")"
fi

fixture
sed -i 's/or `Touches red line` is `yes`/or `Touches redline` is `yes`/' AGENTS.md
if rule > "$work/5b.out" 2>&1; then
    report no "5b a typo in a characteristic name" "no failure reported"
elif grep -q 'reads `Touches redline`, which is not a task characteristic' "$work/5b.out"; then
    report ok "5b a renamed or mistyped characteristic in the table fails, quoting the token" ""
else
    report no "5b characteristic typo" "$(cat "$work/5b.out")"
fi

fixture
sed -i 's/^| 2 — Review |/| 2 — Correctness |/' AGENTS.md
if rule > "$work/5c.out" 2>&1; then
    report no "5c a renamed prompt" "no failure reported"
elif grep -q "prompt 2 is 'Correctness'" "$work/5c.out"; then
    report ok "5c a prompt renamed in the table but not in the sample fails" ""
else
    report no "5c prompt rename" "$(cat "$work/5c.out")"
fi

fixture
python3 - <<'PYEOF'
import io
t = io.open("AGENTS.md", encoding="utf-8").read()
t = t.replace("| 3 — Resolve questions | Before the package, iff an open card in QUESTIONS.md has `Blocks:` = this package. |\n", "")
io.open("AGENTS.md", "w", encoding="utf-8", newline="\n").write(t)
PYEOF
if rule > "$work/5d.out" 2>&1; then
    report no "5d a missing row" "no failure reported"
elif grep -q 'no row for prompt 3' "$work/5d.out"; then
    report ok "5d a prompt with no row in the table fails" ""
else
    report no "5d missing row" "$(cat "$work/5d.out")"
fi

# Prompt 1o is a real prompt, by its exact name: a misspelling selects nothing.
fixture
if rule > "$work/5e.out" 2>&1; then
    report ok "5e the table's row for prompt 1o, Implement (orchestrated), passes" ""
else
    report no "5e prompt 1o" "$(cat "$work/5e.out")"
fi
sed -i 's/^| 1o — Implement (orchestrated) |/| 1o — Implement (orchestrate) |/' AGENTS.md
if rule > "$work/5f.out" 2>&1; then
    report no "5f a misspelled prompt name" "no failure reported"
elif grep -q "prompt 1o is 'Implement (orchestrate)'" "$work/5f.out"; then
    report ok "5f a misspelled prompt name fails, naming the prompt and both spellings" ""
else
    report no "5f misspelled 1o" "$(cat "$work/5f.out")"
fi

# --- 6: blocked-by is live, and reading it writes nothing -----------------------

fixture
cp specs/03-implementation-plan.md "$work/plan.before"
out="$(python3 scripts/check-docs.py --task PKG-02 2>&1)"
if printf '%s' "$out" | grep -q 'blocked-by: Q-002'; then
    report ok "6 --task names the open card whose Blocks: is the package" ""
else
    report no "6 blocked-by" "$out"
fi
# resolve Q-002 the way the log would: it moves to Resolved, nothing else changes
python3 - <<'PYEOF'
import io, re
t = io.open("QUESTIONS.md", encoding="utf-8").read()
card = t[t.index("### Q-002"):t.index("## Resolved")].rstrip() + "\n- Answer: A (2026-09-14)\n"
t = t.replace(card.split("- Answer:")[0], "")            # out of Open
t = t.replace("## Open\n\n\n", "## Open\n\nNone.\n\n")
t = t.replace("## Resolved\n", "## Resolved\n\n" + card)
t = t.replace("— data — Open", "— data — Resolved")
io.open("QUESTIONS.md", "w", encoding="utf-8", newline="\n").write(t)
PYEOF
out="$(python3 scripts/check-docs.py --task PKG-02 2>&1)"
if printf '%s' "$out" | grep -q 'blocked-by: —'; then
    report ok "6b once the card is Resolved the same command returns none" ""
else
    report no "6b blocked-by after resolution" "$out"
fi
if cmp -s "$work/plan.before" specs/03-implementation-plan.md; then
    report ok "6c neither reading changed the implementation plan: blocked-by is never stored" ""
else
    report no "6c plan unchanged" "the plan was rewritten by a --task run"
fi

# --- 7: the fields have to be there, and boolean ------------------------------

fixture
sed -i '/^- Touches red line: yes$/d' specs/03-implementation-plan.md
if rule > "$work/7.out" 2>&1; then
    report no "7 a missing field" "no failure reported"
elif grep -q 'PKG-01 states no `Touches red line:`' "$work/7.out"; then
    report ok "7 a package missing a characteristic fails, naming package and field" ""
else
    report no "7 missing field" "$(cat "$work/7.out")"
fi

fixture
sed -i 's/^- Contract change: yes$/- Contract change: maybe/' specs/03-implementation-plan.md
if rule > "$work/8.out" 2>&1; then
    report no "8 a non-boolean judgement" "no failure reported"
elif grep -q 'PKG-02 has `Contract change: maybe`' "$work/8.out"; then
    report ok "8 \`Contract change\` is checked for shape: a value that is not yes or no fails" ""
else
    report no "8 contract change shape" "$(cat "$work/8.out")"
fi

# the judgement itself is never recomputed: both values pass on the same package
fixture
sed -i 's/^- Contract change: no$/- Contract change: yes/' specs/03-implementation-plan.md
if rule > "$work/9.out" 2>&1; then
    report ok "9 the recorded judgement is not recomputed: either boolean passes on the same package" ""
else
    report no "9 contract change not recomputed" "$(cat "$work/9.out")"
fi

# --- 10: an unknown surface value ----------------------------------------------

fixture
sed -i 's/^- Surfaces: security$/- Surfaces: security, perf/' specs/03-implementation-plan.md
if rule > "$work/10.out" 2>&1; then
    report no "10 an unknown surface" "no failure reported"
elif grep -q 'perf is not a surface' "$work/10.out"; then
    report ok "10 a surface outside the five fails, naming it" ""
else
    report no "10 unknown surface" "$(cat "$work/10.out")"
fi

# --- 12: the file surface and the lane, judged and held to the plan's own list --

fixture
sed -i '/^- File surface: app\/access, tests\/access$/d' specs/03-implementation-plan.md
if rule > "$work/12.out" 2>&1; then
    report no "12 a package with no File surface" "no failure reported"
elif grep -q "PKG-01 states no \`File surface:\`" "$work/12.out" \
     && grep -q 'playbook' "$work/12.out"; then
    report ok "12 a package without its file surface fails, saying what the field is for" ""
else
    report no "12 missing file surface" "$(cat "$work/12.out")"
fi

fixture
sed -i 's/^- Lane: service$/- Lane: whichever is free/' specs/03-implementation-plan.md
if rule > "$work/12b.out" 2>&1; then
    report no "12b a lane the plan does not list" "no failure reported"
elif grep -q "PKG-01 has \`Lane: whichever is free\`" "$work/12b.out" \
     && grep -q 'the lanes are service, tests and infrastructure' "$work/12b.out"; then
    report ok "12b a lane the plan does not define fails, listing the lanes it does" ""
else
    report no "12b unknown lane" "$(cat "$work/12b.out")"
fi

fixture
if rule > "$work/12c.out" 2>&1; then
    report ok "12c the fixture's five characteristics pass, lanes included" ""
else
    report no "12c the five fields" "$(cat "$work/12c.out")"
fi

# The judgement is not recomputed: any surface the author writes is accepted.
sed -i 's|^- File surface: app/totals, tests/totals$|- File surface: everything, frankly|' specs/03-implementation-plan.md
if rule > "$work/12d.out" 2>&1; then
    report ok "12d the file surface is a judgement: the rule never recomputes or second-guesses it" ""
else
    report no "12d judgement not recomputed" "$(cat "$work/12d.out")"
fi

# Two packages in one lane touching one path are not two lanes: reported, not failed.
fixture
sed -i 's|^- File surface: app/totals, tests/totals$|- File surface: app/access, tests/totals|' specs/03-implementation-plan.md
out="$(python3 scripts/check-docs.py --task all 2>&1)"
if printf '%s' "$out" | grep -q "PKG-01 and PKG-02 share lane 'service' and the path(s) app/access"; then
    report ok "12e --task all reports two packages sharing a lane and a path" ""
else
    report no "12e overlap report" "$out"
fi
if rule > "$work/12f.out" 2>&1; then
    report ok "12f the same overlap is reported by the gate and never failed on" ""
else
    report no "12f overlap not a failure" "$(cat "$work/12f.out")"
fi

fixture
out="$(python3 scripts/check-docs.py --brief PKG-01 2>&1)"
if printf '%s' "$out" | grep -q 'Lane: service' && printf '%s' "$out" | grep -q 'File surface: app/access, tests/access'; then
    report ok "12g --brief carries the file surface and the lane: the packet's allowed scope" ""
else
    report no "12g brief fields" "$(printf '%s' "$out" | head -8)"
fi

# --- 11: --brief selects the pack, in order, and never writes -------------------

fixture
cat > PLAN.md <<'EOF'
# PLAN

## Now

### PKG-01 — Keeper access

- **Outcome:** the ownership rule of `01` §2 holds in one place.
- **Dependencies:** PKG-02.

## Next

1. PKG-03.
EOF
cat > TRACEABILITY.md <<'EOF'
# TRACEABILITY

| Package | Phase | Outcome | Key specs | Status | Evidence |
| --- | --- | --- | --- | --- | --- |
| PKG-01 | 0 | Keeper access | `01` §2 | not started | — |
| PKG-02 | 0 | Totals | `01` §1 | done | 2026-09-22: TotalsTest |
| PKG-03 | 0 | Keeper access, one line | `01` §2 | not started | — |
EOF
cat > GAPS.md <<'EOF'
# GAPS

| ID | Gap | Consequence | Evidence to close | Plan item |
| --- | --- | --- | --- | --- |
| G-001 | No ownership check exists yet. | Anyone could read a notebook. | A test naming the refusal. | PKG-01 |
| G-002 | Totals are not paged. | Long notebooks are slow. | A measurement. | PKG-09 |
EOF
cat > DECISIONS.md <<'EOF'
# DECISIONS

## Index

- D-001 — Change control regime

## D-001 (2026-09-14) — Change control regime
Type: implementation
Decision: a proposed change to the register requires an ADR.
Why: the register is the owner's.
Alternatives: none weighed.
Affected specs: `02` §6.
EOF
mkdir -p docs/layers
printf '# PKG-02 — the totals layer\n\n## What this package established\n\n`Totals::forMonth()` is the only reader.\n\n## What a later slice must not do\n\nDo not store a total.\n\n## Handoff\n\n### 2026-09-22\n\n- Changed: the totals module.\n' > docs/layers/PKG-02.md

# The package block and the `Now` item both cite `01` §2: the brief resolves each
# section once, so the count is 1 rather than 2.
cp specs/03-implementation-plan.md "$work/plan.before11"
out="$(python3 scripts/check-docs.py --brief PKG-01 2>&1)"
order="$(printf '%s' "$out" | grep -oE '^--- [a-zA-Z].*' | sed -E 's/ -+$//')"
expected="--- characteristics (prompt selection: AGENTS.md)
--- PLAN.md \`Now\`
--- implementation plan: the package
--- cards blocking this package (0)
--- spec sections cited (1)
--- decisions cited (0)
--- layer notes of the packages this one names (1 of 1)
--- TRACEABILITY.md
--- GAPS.md rows naming PKG-01 (1)
--- end of brief"
if [ "$order" = "$expected" ]; then
    report ok "11 --brief prints every section once, in the fixed order, with its counts" ""
else
    report no "11 brief order" "$(printf '%s' "$order" | head -12)"
fi

if printf '%s' "$out" | grep -q 'A notebook MUST be readable by its keeper only' \
   && printf '%s' "$out" | grep -q '`Totals::forMonth()` is the only reader' \
   && printf '%s' "$out" | grep -q 'G-001' && ! printf '%s' "$out" | grep -q 'G-002' \
   && printf '%s' "$out" | grep -q '| PKG-01 | 0 |' && ! printf '%s' "$out" | grep -q '| PKG-02 | 0 |'; then
    report ok "11b --brief carries the cited spec text, the dependency's layer note, and only the rows naming this package" ""
else
    report no "11b brief content" "$(printf '%s' "$out" | tail -20)"
fi

if printf '%s' "$out" | grep -qE '^[0-9]+ bytes above this line'; then
    report ok "11c --brief ends with its own byte count: the package's reading cost" ""
else
    report no "11c byte count" "$(printf '%s' "$out" | tail -4)"
fi

if cmp -s "$work/plan.before11" specs/03-implementation-plan.md; then
    report ok "11d a brief writes nothing: the plan is byte-identical after it" ""
else
    report no "11d brief writes" "the plan changed"
fi

if python3 scripts/check-docs.py --brief PKG-99 > "$work/11e.out" 2>&1; then
    report no "11e an unknown package" "exited 0"
elif grep -q 'PKG-99 is not a work package' "$work/11e.out"; then
    report ok "11e an unknown package exits non-zero, naming it" ""
else
    report no "11e unknown package" "$(cat "$work/11e.out")"
fi

# The card blocking PKG-02 is carried in full, and resolving it changes the brief
# with no edit to the plan - the same guarantee --task has, now over the material.
out2="$(python3 scripts/check-docs.py --brief PKG-02 2>&1)"
if printf '%s' "$out2" | grep -q 'cards blocking this package (1)' \
   && printf '%s' "$out2" | grep -q 'B) Purge after N years'; then
    report ok "11f --brief carries the blocking card in full, options included" ""
else
    report no "11f blocking card" "$(printf '%s' "$out2" | head -30)"
fi

# A section renumbered would be a different citation; a section RETITLED is not.
sed -i 's/^## 2. Access$/## 2. Access and ownership/' specs/01-scope.md
out3="$(python3 scripts/check-docs.py --brief PKG-01 2>&1)"
if printf '%s' "$out3" | grep -q '`01` §2 Access and ownership' \
   && printf '%s' "$out3" | grep -q 'A notebook MUST be readable by its keeper only'; then
    report ok "11g a retitled section still resolves: the brief reads the number, not the words" ""
else
    report no "11g retitled section" "$(printf '%s' "$out3" | grep -A3 'spec sections')"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
