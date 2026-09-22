#!/bin/sh
# Rule-level acceptance test for check-docs.py: each case builds the smallest
# fixture that exercises one rule and runs that rule's function directly, in a
# fresh process so the module-level failure list starts empty. Runs in a
# throwaway directory; needs no git.
#
#   scripts/test-check-docs.sh [--keep]
#
# The render-and-check suite (test-render.sh) covers the whole gate over the
# shipped templates; this file is for the rules one at a time.
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
mkdir -p "$repo/scripts"
cd "$repo" || exit 2
cp "$tpl/scripts/check-docs.py" scripts/check-docs.py

# probe <python statements>: load check-docs.py as a module, run the statements,
# print every FAIL line, exit 1 if there was one.
probe() {
    python3 - "$1" <<'PROBEEOF'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("checkdocs", "scripts/check-docs.py")
cd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cd)
root = os.path.abspath(".")
exec(sys.argv[1])
for line in cd.failures:
    print(line)
sys.exit(1 if cd.failures else 0)
PROBEEOF
}

printf 'check-docs rule acceptance\n'

# --- markers: the Makefile is scanned -----------------------------------------

printf 'help: ## {{PRODUCT_NAME}} targets\n\t@true\n' > Makefile
if probe 'cd.check_markers(root, [os.path.join(root, "Makefile")])' > "$work/m1.out" 2>&1; then
    report no "markers: a placeholder in the Makefile" "no failure reported"
elif grep -q 'FAIL markers .*Makefile:1' "$work/m1.out"; then
    report ok "markers: an unrendered placeholder in the Makefile fails, naming the line" ""
else
    report no "markers: Makefile" "$(cat "$work/m1.out")"
fi

printf 'help: ## Rendered targets\n\t@true\n' > Makefile
if probe 'cd.check_markers(root, [os.path.join(root, "Makefile")])' > "$work/m2.out" 2>&1; then
    report ok "markers: a rendered Makefile passes" ""
else
    report no "markers: rendered Makefile" "$(cat "$work/m2.out")"
fi

# main() has to hand the Makefile to the rule; the function alone proves nothing
if grep -q 'check_markers(root, all_docs + (\[makefile\]' scripts/check-docs.py; then
    report ok "markers: main() passes the root Makefile to the rule" ""
else
    report no "markers: main() wiring" "main() does not include the Makefile"
fi

# --- cards: IDs are contiguous from Q-001 --------------------------------------

card() {  # card <id> <section-state label unused>
    cat <<CARDEOF

### $1 — A card
- Surface: data
- Source: the fixture
- Question: Is this contiguous?
- Options:
  - A) yes → effect on data: none.
  - B) no → effect on data: none.
- Recommendation: A, because it is a fixture.
- Blocks: specification
CARDEOF
}

{
    printf '# QUESTIONS\n\n## Index\n\n- Q-001 — A card — data — Blocking\n- Q-003 — A card — data — Blocking\n\n## Blocking\n'
    card Q-001; card Q-003
    printf '\n## Open\n\nNone.\n\n## Resolved\n\nNone.\n'
} > QUESTIONS.md
if probe 'cards, resolved, sup = cd.parse_cards(root); cd.check_cards(cards)' > "$work/c1.out" 2>&1; then
    report no "cards: a gap in the IDs" "Q-002 missing went unreported"
elif grep -q 'not contiguous from Q-001; missing Q-002' "$work/c1.out"; then
    report ok "cards: a gap in the card IDs fails, naming the missing ID" ""
else
    report no "cards: gap" "$(cat "$work/c1.out")"
fi

{
    printf '# QUESTIONS\n\n## Index\n\n- Q-001 — A card — data — Blocking\n- Q-002 — A card — data — Blocking\n\n## Blocking\n'
    card Q-001; card Q-002
    printf '\n## Open\n\nNone.\n\n## Resolved\n\nNone.\n'
} > QUESTIONS.md
if probe 'cards, resolved, sup = cd.parse_cards(root); cd.check_cards(cards)' > "$work/c2.out" 2>&1; then
    report ok "cards: contiguous IDs pass" ""
else
    report no "cards: contiguous" "$(cat "$work/c2.out")"
fi

# --- normative-tagged ----------------------------------------------------------

mkdir -p specs docs/inputs
cat > specs/01-scope.md <<'EOF'
# Scope

## 1. Rules

- The service MUST reject an unknown keeper. [input]
- Entries MUST carry a date.
- The word `MUST` in a code span is a mention, not a statement.

```
A fenced MUST is not a statement either.
```

| Column | A table row MUST not count |
| --- | --- |

The agent MUST: [D-005]

1. inspect before editing;
2. add tests in the same change; [input]

Prose after the list ends the inheritance. MAY this be caught?
EOF
if probe 'cd.check_normative(root, False)' > "$work/n1.out" 2>&1; then
    report no "normative-tagged: untagged statements" "no failure reported"
elif [ "$(grep -c 'FAIL normative-tagged' "$work/n1.out")" = "2" ] && grep -q 'specs/01-scope.md:6' "$work/n1.out" && grep -q 'specs/01-scope.md:21' "$work/n1.out"; then
    report ok "normative-tagged: exactly the two untagged statements fail (lines 6 and 21); code span, fence, table and inherited items do not" ""
else
    report no "normative-tagged: detection" "$(cat "$work/n1.out")"
fi

sed -i 's/^- Entries MUST carry a date\.$/- Entries MUST carry a date. [inferred]/; s/^Prose after the list ends the inheritance. MAY this be caught?$/Prose after the list ends the inheritance. MAY this be caught? [D-001]/' specs/01-scope.md
if probe 'cd.check_normative(root, False)' > "$work/n2.out" 2>&1; then
    report ok "normative-tagged: passes once every statement carries a tag" ""
else
    report no "normative-tagged: tagged fixture" "$(cat "$work/n2.out")"
fi

# an adopted pack is exempt by the declaration in docs/inputs/README.md
sed -i 's/ \[inferred\]$//' specs/01-scope.md
printf '# Inputs\n\n| File | Received | Kind | Authority |\n| --- | --- | --- | --- |\n| `specs/` | 2026-09-08 | prior specification | authoritative |\n' > docs/inputs/README.md
if probe 'a = cd.adopted_pack(root); assert a, "not detected as adopted"; cd.check_normative(root, a)' > "$work/n3.out" 2>&1; then
    report ok "normative-tagged: an adopted pack (specs/ declared authoritative) is exempt" ""
else
    report no "normative-tagged: adopted pack" "$(cat "$work/n3.out")"
fi
rm docs/inputs/README.md

# --- inferred-zero -------------------------------------------------------------

printf '# Specs\n\nVersion: 0.1-draft  \nStatus: Draft, not yet an implementation baseline  \n' > specs/README.md
if probe 'cd.check_inferred({"specs/01-scope.md": 1}, cd.frozen(root))' > "$work/i1.out" 2>&1; then
    report ok "inferred-zero: a draft pack with [inferred] passes (reported, not enforced)" ""
else
    report no "inferred-zero: draft" "$(cat "$work/i1.out")"
fi
printf '# Specs\n\nVersion: 1.0  \nStatus: Implementation baseline, 2026-09-08  \n' > specs/README.md
if probe 'cd.check_inferred({"specs/01-scope.md": 1}, cd.frozen(root))' > "$work/i2.out" 2>&1; then
    report no "inferred-zero: frozen pack with [inferred]" "no failure reported"
elif grep -q 'FAIL inferred-zero .*specs/01-scope.md' "$work/i2.out"; then
    report ok "inferred-zero: the same [inferred] fails once the baseline is stamped" ""
else
    report no "inferred-zero: frozen" "$(cat "$work/i2.out")"
fi
if probe 'cd.check_inferred({}, cd.frozen(root))' > "$work/i3.out" 2>&1; then
    report ok "inferred-zero: a frozen pack with none passes" ""
else
    report no "inferred-zero: frozen clean" "$(cat "$work/i3.out")"
fi

# --- the skill's extract-normative reads the same detector --------------------

if python3 "$here/scripts/extract-normative.py" --specs specs --untagged 2>/dev/null | grep -q 'Entries MUST carry a date'; then
    report ok "extract-normative lists the untagged statement through the shared detector" ""
else
    report no "extract-normative" "did not list the untagged statement"
fi

# --- citations: superseded decisions are history; §Name reads the longest heading ---

rm -rf specs docs; mkdir -p specs
printf '# Specs\n\n## Provenance\n\nTags.\n\n## Conflict resolution\n\nOrder.\n' > specs/README.md
printf '# Scope\n\n## 1. Purpose\n\nText.\n' > specs/01-scope.md
cat > DECISIONS.md <<'EOF'
# DECISIONS

## Index

- D-001 — Old — implementation — superseded by D-002
- D-002 — New — implementation

## D-001 (2026-09-08) — Old
Status: superseded by D-002
Type: implementation
Decision: cites `01` §9, which never existed.
Why: history.
Alternatives: none.
Affected specs: `01` §9.

## D-002 (2026-09-08) — New
Type: implementation
Decision: cites `01` §1 and `specs/README.md` §Provenance says that tags are trailing.
Why: live.
Alternatives: none.
Affected specs: `01` §1.
EOF
if probe 'n, m = cd.section_index(root); cd.check_citations(root, [os.path.join(root, "DECISIONS.md")], n, m)' > "$work/ct1.out" 2>&1; then
    report ok "citations: a dead citation inside a superseded decision is history and passes; §Name followed by prose resolves" ""
else
    report no "citations: superseded / prose" "$(cat "$work/ct1.out")"
fi
sed -i 's/^Decision: cites `01` §1 and/Decision: cites `01` §9 and/' DECISIONS.md
if probe 'n, m = cd.section_index(root); cd.check_citations(root, [os.path.join(root, "DECISIONS.md")], n, m)' > "$work/ct2.out" 2>&1; then
    report no "citations: dead citation in a live decision" "passed"
elif grep -q 'DECISIONS.md:18: `01` §9 does not resolve' "$work/ct2.out"; then
    report ok "citations: the same dead citation in a live decision fails, on its line" ""
else
    report no "citations: live dead" "$(cat "$work/ct2.out")"
fi
printf 'See `specs/README.md` §Nonexistent thing for details.\n' > AGENTS.md
if probe 'n, m = cd.section_index(root); cd.check_citations(root, [os.path.join(root, "AGENTS.md")], n, m)' > "$work/ct3.out" 2>&1; then
    report no "citations: unknown §Name" "passed"
elif grep -q '§Nonexistent thing for details' "$work/ct3.out"; then
    report ok "citations: an unknown §Name fails, quoting the words that did not match" ""
else
    report no "citations: unknown name" "$(cat "$work/ct3.out")"
fi
# the same parser, exposed for log-append: a not-yet-written spec is not a failure with existing_only
if probe 'f = cd.citation_failures(root, "cites `01` §9 and `07` §3 and `specs/07-plan.md`", existing_only=True); assert f == ["`01` §9 does not resolve"], f' > "$work/ct4.out" 2>&1; then
    report ok "citations: citation_failures(existing_only) flags only the section missing from an existing spec" ""
else
    report no "citations: existing_only" "$(cat "$work/ct4.out")"
fi
rm -f AGENTS.md DECISIONS.md

# --- normative-tagged covers the spec map; --only scopes a run ------------------

mkdir -p specs
printf '# Specs\n\n## Product statement\n\n> The tool MUST record entries.\n\n## Technology baseline\n\n- Python. [input]\n' > specs/README.md
if probe 'cd.check_normative(root, False)' > "$work/rm1.out" 2>&1; then
    report no "normative-tagged: untagged MUST in specs/README.md" "not reported"
elif grep -q 'FAIL normative-tagged specs/README.md:5' "$work/rm1.out"; then
    report ok "normative-tagged: an untagged statement in the spec map fails on its line" ""
else
    report no "normative-tagged: spec map" "$(cat "$work/rm1.out")"
fi
rm -rf specs docs
mkdir -p specs; printf '# S\n\n## 1. X\n\n- It MUST work.\n' > specs/01-x.md
out="$(python3 scripts/check-docs.py --quiet --only normative-tagged 2>&1)"
if echo "$out" | grep -q '^FAIL normative-tagged' && ! echo "$out" | grep -q '^FAIL packages' && echo "$out" | grep -q 'failure(s) of other rules dropped by --only'; then
    report ok "--only keeps the named rule's failures and says how many others it dropped" ""
else
    report no "--only" "$(echo "$out" | head -8)"
fi
rm -rf specs

# --- gaps-size and evidence-size: a register row is not a chronicle ------------

mkdir -p specs
cat > specs/03-implementation-plan.md <<'PLANEOF'
# Implementation Plan

## 3. Phase 0 — Foundations

### Work packages

`PKG-01` One

- Surfaces: —
PLANEOF
long="$(python3 -c "print('narrative about how three packages narrowed this gap. ' * 50)")"
printf '# GAPS\n\n| ID | Gap | Consequence | Evidence to close | Plan item |\n| --- | --- | --- | --- | --- |\n| G-001 | %s | It costs. | A test. | PKG-01 |\n' "$long" > GAPS.md
if probe 'cd.check_gaps(root, {"PKG-01"}, {"0"})' > "$work/g1.out" 2>&1; then
    report no "gaps-size: an oversized Gap cell" "not reported"
elif grep -q 'FAIL gaps-size .*GAPS.md:5: G-001 has a cell of [0-9]* characters' "$work/g1.out"; then
    report ok "gaps-size: a Gap cell past the ceiling fails, naming the length" ""
else
    report no "gaps-size: oversized cell" "$(cat "$work/g1.out")"
fi

printf '# GAPS\n\n| ID | Gap | Consequence | Evidence to close | Plan item |\n| --- | --- | --- | --- | --- |\n| G-001 | Nothing checks ownership. | Anyone reads anything. | A test naming the refusal. | PKG-01 |\n' > GAPS.md
if probe 'cd.check_gaps(root, {"PKG-01"}, {"0"})' > "$work/g2.out" 2>&1; then
    report ok "gaps-size: a row that states one gap passes" ""
else
    report no "gaps-size: normal row" "$(cat "$work/g2.out")"
fi

printf '# GAPS\n\n| ID | Gap | Consequence | Evidence to close | Plan item |\n| --- | --- | --- | --- | --- |\n| G-001 | PKG-01 narrowed it, PKG-02 narrowed it, PKG-03 narrowed it and PKG-04 rewrote it. | It costs. | A test. | PKG-01 |\n' > GAPS.md
out="$(python3 - <<'PROBE2'
import importlib.util, os
spec = importlib.util.spec_from_file_location("checkdocs", "scripts/check-docs.py")
cd = importlib.util.module_from_spec(spec); spec.loader.exec_module(cd)
cd.check_gaps(os.path.abspath("."), {"PKG-01", "PKG-02", "PKG-03", "PKG-04"}, {"0"})
print("\n".join(cd.notes)); print("FAILURES:", len(cd.failures))
PROBE2
)"
if printf '%s' "$out" | grep -q 'note gaps-size .*names 4 work packages' && printf '%s' "$out" | grep -q 'FAILURES: 0'; then
    report ok "gaps-size: a row naming four packages is reported and never failed on" ""
else
    report no "gaps-size: the report" "$out"
fi
rm -f GAPS.md

long_ev="$(python3 -c "print('2026-09-01: the suite passed; 2026-09-02: it passed again. ' * 20, end='')")"
printf '# TRACEABILITY\n\n| Package | Phase | Outcome | Key specs | Status | Evidence |\n| --- | --- | --- | --- | --- | --- |\n| PKG-01 | 0 | One | `01` §1 | done | %s |\n' "$long_ev" > TRACEABILITY.md
if probe 'cd.check_packages_and_traceability(root)' > "$work/e1.out" 2>&1; then
    report no "evidence-size: an oversized Evidence cell" "not reported"
elif grep -q 'FAIL evidence-size .*TRACEABILITY.md:5: PKG-01 has [0-9]* characters of evidence' "$work/e1.out"; then
    report ok "evidence-size: an Evidence cell past the ceiling fails, naming the length" ""
else
    report no "evidence-size: oversized cell" "$(cat "$work/e1.out")"
fi

printf '# TRACEABILITY\n\n| Package | Phase | Outcome | Key specs | Status | Evidence |\n| --- | --- | --- | --- | --- | --- |\n| PKG-01 | 0 | One | `01` §1 | done | 2026-09-22: `make verify` exit 0; OwnershipTest, TotalsTest. |\n' > TRACEABILITY.md
if probe 'cd.check_packages_and_traceability(root)' > "$work/e2.out" 2>&1; then
    report ok "evidence-size: the run that proved the current status passes" ""
else
    report no "evidence-size: normal evidence" "$(cat "$work/e2.out")"
fi
rm -f TRACEABILITY.md
rm -rf specs

# --- layer-notes: the note exists for what is done, the index never holds one --

mkdir -p docs/layers
printf '# AGENTS.md\n\n## Layer notes\n\nNone yet: no package has been delivered.\n' > AGENTS.md
rows='{"FND-01": (3, "done", "ran"), "FND-02": (4, "not started", "\u2014")}'
pkgs='{"FND-01", "FND-02"}'

if probe "cd.check_layer_notes(root, $pkgs, $rows)" > "$work/l1.out" 2>&1; then
    report no "layer-notes: a done package with no note" "not reported"
elif grep -q 'FAIL layer-notes .*docs/layers/FND-01.md.*`done`.*no layer note' "$work/l1.out"; then
    report ok "layer-notes: a done package without a note fails, naming the file it owes" ""
else
    report no "layer-notes: missing note" "$(cat "$work/l1.out")"
fi

note() {  # note <path> <headings...>
    p="$1"; shift
    printf '# FND-01 — the command contract\n' > "$p"
    for h in "$@"; do printf '\n## %s\n\nx\n' "$h" >> "$p"; done
}
note docs/layers/FND-01.md "What this package established" "Handoff"
if probe "cd.check_layer_notes(root, $pkgs, $rows)" > "$work/l2.out" 2>&1; then
    report no "layer-notes: a note missing a heading" "not reported"
elif grep -q 'FAIL layer-notes .*docs/layers/FND-01.md: no `## What a later slice must not do`' "$work/l2.out"; then
    report ok "layer-notes: a note missing one of the three headings fails, naming the heading" ""
else
    report no "layer-notes: headings" "$(cat "$work/l2.out")"
fi

note docs/layers/FND-01.md "What this package established" "What a later slice must not do" "Handoff"
if probe "cd.check_layer_notes(root, $pkgs, $rows)" > "$work/l3.out" 2>&1; then
    report no "layer-notes: a note the index does not carry" "not reported"
elif grep -q 'FAIL layer-notes .*AGENTS.md: FND-01 has a layer note that the `Layer notes` index does not carry' "$work/l3.out"; then
    report ok "layer-notes: a note absent from the AGENTS.md index fails" ""
else
    report no "layer-notes: index" "$(cat "$work/l3.out")"
fi

printf '# AGENTS.md\n\n## Layer notes\n\n- FND-01 — the command contract → `docs/layers/FND-01.md`\n' > AGENTS.md
if probe "cd.check_layer_notes(root, $pkgs, $rows)" > "$work/l4.out" 2>&1; then
    report ok "layer-notes: a done package with its note and its index line passes" ""
else
    report no "layer-notes: clean fixture" "$(cat "$work/l4.out")"
fi

cp "$tpl/docs-layers-README.md" docs/layers/README.md
printf 'x\n' > docs/layers/_SCRATCH.md
if probe "cd.check_layer_notes(root, $pkgs, $rows)" > "$work/l5.out" 2>&1; then
    report ok "layer-notes: the shipped README and an underscore-prefixed file are not read as notes" ""
else
    report no "layer-notes: shipped files" "$(cat "$work/l5.out")"
fi

touch docs/layers/XXX-99.md
if probe "cd.check_layer_notes(root, $pkgs, $rows)" > "$work/l6.out" 2>&1; then
    report no "layer-notes: a note naming no package" "not reported"
elif grep -q 'FAIL layer-notes .*docs/layers/XXX-99.md: names no work package' "$work/l6.out"; then
    report ok "layer-notes: a note whose name is not a package in the plan fails" ""
else
    report no "layer-notes: orphan note" "$(cat "$work/l6.out")"
fi
rm docs/layers/XXX-99.md

printf '\n## The FND-02 layer every later slice builds on\n\nprose\n' >> AGENTS.md
if probe "cd.check_layer_notes(root, $pkgs, $rows)" > "$work/l7.out" 2>&1; then
    report no "layer-notes: an AGENTS.md heading naming a package" "not reported"
elif grep -q 'FAIL layer-notes .*AGENTS.md:[0-9]*: heading names the work package FND-02' "$work/l7.out"; then
    report ok "layer-notes: a section per package in AGENTS.md fails, naming the note it belongs in" ""
else
    report no "layer-notes: per-package heading" "$(cat "$work/l7.out")"
fi

# main() has to run the rule; the function alone proves nothing
if grep -q 'check_layer_notes(root, pkgs, rows)' scripts/check-docs.py; then
    report ok "layer-notes: main() runs the rule with the plan's packages and the traceability rows" ""
else
    report no "layer-notes: main() wiring" "main() does not call check_layer_notes"
fi
rm -rf docs AGENTS.md

# --- the lookup does not drift from the code it documents ----------------------
# A reference that goes stale is worse than none: the agent that trusts it stops
# looking. Both halves are derived from the sources, never from a list here.

ref="$here/reference/events-and-rules.md"
python3 - "$ref" "$tpl/scripts/check-docs.py" "$tpl/scripts/eventlog.py" > "$work/drift.out" 2>&1 <<'DRIFTEOF'
import re, sys
ref, checker, eventlog = (open(p, encoding="utf-8").read() for p in sys.argv[1:4])
problems = []

# Every rule the checker can name, against every rule the lookup tabulates.
in_code = set(re.findall(r'(?:fail|ok|note)\("([a-z][a-z-]+)"', checker))
rules_section = ref.split("## `check-docs`: the rule names", 1)[-1]
in_ref = set(re.findall(r'^\| `([a-z][a-z-]+)` \|', rules_section, re.M))
for name in sorted(in_code - in_ref):
    problems.append("rule %s exists in check-docs.py and is not in the lookup" % name)
for name in sorted(in_ref - in_code):
    problems.append("the lookup names rule %s, which check-docs.py does not have" % name)

# Every event type, and the fields eventlog.py requires of it.
for const in ("DECISION_EVENTS", "CARD_EVENTS"):
    m = re.search(r"^%s = \(([^)]*)\)" % const, eventlog, re.M | re.S)
    for event in re.findall(r'"([a-z-]+)"', m.group(1)):
        if "`%s`" % event not in ref:
            problems.append("event %s is not in the lookup" % event)
m = re.search(r'^DECISION_FIELDS = \(([^)]*)\)', eventlog, re.M | re.S)
for field in re.findall(r'"([a-z_]+)"', m.group(1)):
    if "`%s`" % field not in ref:
        problems.append("decision-added requires %s and the lookup does not name it" % field)

print("\n".join(problems) if problems else "no drift")
sys.exit(1 if problems else 0)
DRIFTEOF
if [ $? -eq 0 ]; then
    report ok "lookup: reference/events-and-rules.md names every rule and every event the code has" ""
else
    report no "lookup drift" "$(cat "$work/drift.out")"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
