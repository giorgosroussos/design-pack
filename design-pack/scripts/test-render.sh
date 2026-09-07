#!/bin/sh
# Render-and-check acceptance test: the whole gate over the shipped templates.
#
# Renders every template with the placeholder values of a small fixture product,
# following stages/C-operationalize.md Step C1 and the truthful-empty state of
# Step C2, seeds the log with the four regime records and two cards, writes the
# smallest specs/ set the templates' cross-references resolve against, then
# asserts that the result is a pack `make check-docs` accepts. The rule-level
# suite is test-check-docs.sh; this one proves the templates and the gate agree.
#
#   scripts/test-render.sh [--keep]
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

report() {  # report <ok|no> <case> <message>
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
mkdir -p "$repo"
cd "$repo" || exit 2

if command -v make >/dev/null 2>&1; then HAVE_MAKE=1; else HAVE_MAKE=""; printf '  NOTE  make is not installed; calling the scripts directly\n'; fi
check_docs()   { if [ -n "$HAVE_MAKE" ]; then make check-docs; else python3 scripts/verify-chain.py && python3 scripts/check-docs.py; fi; }
check_locks()  { if [ -n "$HAVE_MAKE" ]; then make check-locks; else python3 scripts/lock-guard.py --staged; fi; }
verify_chain() { if [ -n "$HAVE_MAKE" ]; then make verify-chain; else python3 scripts/verify-chain.py; fi; }
install_hooks() {
    if [ -n "$HAVE_MAKE" ]; then make install-hooks
    else git config core.hooksPath .githooks; chmod +x .githooks/pre-commit .githooks/post-commit .githooks/pre-receive; fi
}

# --- Step C1: verbatim assets -------------------------------------------------

mkdir -p scripts .githooks .log docs/inputs specs
for f in check-docs.py lock-guard.py unlock.sh eventlog.py log-append.py rebuild-decisions.py rebuild-questions.py verify-chain.py; do
    cp "$tpl/scripts/$f" "scripts/$f"
done
chmod +x scripts/check-docs.py scripts/lock-guard.py scripts/unlock.sh scripts/log-append.py \
         scripts/rebuild-decisions.py scripts/rebuild-questions.py scripts/verify-chain.py
cp "$tpl/.doc-locks" .doc-locks
for f in pre-commit post-commit pre-receive README.md; do cp "$tpl/githooks/$f" ".githooks/$f"; done
chmod +x .githooks/pre-commit .githooks/post-commit .githooks/pre-receive
printf '.doc-unlock\n__pycache__/\n' > .gitignore

# --- rendering ----------------------------------------------------------------
# One renderer for every template: strip the TEMPLATE NOTES block, drop the
# conditional blocks the fixture does not use (no API, no UI, no generated
# contract), substitute the placeholders, and refuse to write a file that still
# carries a `{{` so a missing value fails here with its name, not later in the gate.

TPL="$tpl" python3 - <<'PYEOF'
import os, re, sys

tpl = os.environ["TPL"]
DATE = "2026-09-08"

# Spec numbers by role. The fixture has no API and no UI, so FND-03 and FND-04
# are dropped and there is no contract-drift target.
NN = dict(SCOPE="01", ARCH="02", SECURITY="03", TESTING="04", TRACE="05", REGISTER="06", PLAN="07", PLAYBOOK="08")

P = {
    "PRODUCT_NAME": "Ledgerette",
    "DATE": DATE,
    "NN_SCOPE": NN["SCOPE"], "NN_ARCH": NN["ARCH"], "NN_TESTING": NN["TESTING"], "NN_TRACE": NN["TRACE"],
    "NN_REGISTER": NN["REGISTER"], "NN_PLAN": NN["PLAN"], "NN_PLAYBOOK": NN["PLAYBOOK"],
    "REGISTER_CC_SECTION": "6",
    "ISOLATION_TERM": "notebook isolation",
    "ISOLATION_AXIS": "notebook",
    "INFRA_SERVICES": "PostgreSQL",
    "PRIMARY_DB": "PostgreSQL 16",
    "STACK_SCAFFOLD_BULLET": "Create the single service application and its test harness as `02` §1 lays them out.",
    "STACK_LINE": "one Python service, PostgreSQL, no web UI in MVP.",
    "ONE_LINE": "A single-user bookkeeping notebook: entries in, monthly totals out. Not an accounting system, not multi-user.",
    # PLAN.md
    "NEXT_ITEMS": "1. FND-02 — CI baseline: every job runs one `Makefile` target against PostgreSQL 16 (`07` §3).",
    # GAPS.md
    "EXTRA_ROWS": "",
    # TRACEABILITY.md
    "JOURNEYS_SECTION_REF": "§4",
    "PHASE_EXIT_RANGE": "§3–4",
    "PACKAGE_ROWS": "\n".join([
        "| FND-01 | 0 | Command contract and repository scaffold | `07` §3 | not started | — |",
        "| FND-02 | 0 | CI baseline | `07` §3 | not started | — |",
        "| LDG-01 | 1 | Notebook and entry model with migrations | `07` §4, `01` §2 | not started | — |",
        "| LDG-02 | 1 | Monthly totals | `07` §4, `01` §3 | not started | — |",
    ]),
    "JOURNEY_ROWS": "\n".join([
        "| 1 | Record an entry and see it in the month's total | not started | — |",
        "| 2 | Correct an entry; the total follows | not started | — |",
    ]),
    # CLAUDE.md
    "GENERATED_ARTIFACT_LINE": "",
    "NON_AUTHORITATIVE_LINE": "",
    # docs/inputs/README.md and specs/traceability.md both use {{ROWS}}; set below, per file.
    "CONFLICT_PARAGRAPH": "No non-authoritative input was received.",
    "ABSENT_PARAGRAPH": "The inputs fix no hosting location and no retention period; both are cards (`QUESTIONS.md` Q-002 for retention).",
    # AGENTS.md
    "PRODUCT_PARAGRAPH": "Ledgerette is a single-user bookkeeping notebook (`specs/README.md` product statement). One actor, the keeper, records dated entries into a notebook and reads monthly totals (`01` §2). It is not an accounting system and has no sharing (`01` §3).",
    "MVP_SUCCESS_SENTENCE": "The MVP succeeds when a keeper can record a month of entries and the total matches a hand sum (`01` §4).",
    "TESTING_RELEASE_SECTION": "5",
    "TESTING_JOURNEYS_SECTION": "4",
    "PLAN_PARALLEL_SECTION": "5",
    "PLAN_LAST_PHASE_SECTION": "4",
    "NON_AUTHORITATIVE_PARAGRAPH": "**Non-authoritative inputs (D-003).** None were received. Any mockup, competitor reference or prior draft added later gets an authority entry in `docs/inputs/README.md` and a `DECISIONS.md` entry before use.",
    "RED_LINES": "\n".join([
        "- **One notebook per keeper.** An entry belongs to exactly one notebook and a notebook to exactly one keeper (`01` §2, `06` §1).",
        "- **No sharing in MVP.** Notebooks are private; no read access for anyone but the keeper (`03` §1, `06` §2).",
        "- **Real database in tests.** `make test` runs against PostgreSQL, never a lighter substitute (`04` §1).",
        "- **Totals are derived, never stored.** A monthly total is computed from entries at read time (`01` §3).",
    ]),
    "STACK_PARAGRAPH": "One Python service with PostgreSQL as the only store (`02` §1). No web UI and no API are part of MVP (`01` §3).",
    "LAYOUT_BLOCK": "ledgerette/\n  app/        the service\n  tests/      the test harness\n  migrations/ schema changes",
    "TOPOLOGY_PARAGRAPH": "A single host runs the service and PostgreSQL (`02` §2). Tooling the specs leave open is chosen in `DECISIONS.md`.",
    "CONTRACT_DRIFT_TARGET_LINE": "",
    "DESIGN_DIRECTION_SECTION": "",
    # SESSION_BOOTSTRAP_PROMPT_SAMPLE.md
    "CONTRACT_SENTENCE": "Update the shared type definitions whenever a contract changes.",
    "REVIEW_PASS_2": "attempt cross-notebook reads and writes and wrong-keeper access",
    "REVIEW_PASS_4": "not applicable: no UI in MVP",
    # specs/README.md
    "PRODUCT_STATEMENT": "Ledgerette is a single-user bookkeeping notebook that records dated entries and derives monthly totals; it is not an accounting system and has no sharing. [input]",
    "TECH_BASELINE_BULLETS": "- Python service. [input]\n- PostgreSQL as the only store. [input]",
    "FILE_TABLE_ROWS": "\n".join([
        "| `01-scope-actors.md` | Actors, MVP boundary, success criterion |",
        "| `02-architecture.md` | Layout and topology |",
        "| `03-security.md` | Access and isolation |",
        "| `04-testing-acceptance.md` | Test layers, gates, journeys, release gate |",
        "| `05-traceability.md` | Product-intent scope matrix |",
        "| `06-decision-register.md` | Locked owner decisions |",
        "| `07-implementation-plan.md` | Phases and work packages |",
        "| `08-agent-playbook.md` | How implementation agents work |",
    ]),
    # specs/decision-register.md
    "DATA_BULLETS": "- An entry belongs to exactly one notebook; a notebook to exactly one keeper. [input]",
    "SECURITY_BULLETS": "- Notebooks are private to their keeper; no sharing in MVP. [Q-001]",
    "SCOPE_BULLETS": "- No web UI and no API in MVP. [input]",
    "EXTERNAL_BULLETS": "No locked decision on this surface.",
    "UX_BULLETS": "No locked decision on this surface.",
    # specs/implementation-plan.md
    "DEPENDENCY_GRAPH": "flowchart LR\n  P0[Phase 0] --> P1[Phase 1]",
    "DOMAIN_PHASES": "\n".join([
        "## 4. Phase 1 — Ledger core",
        "",
        "Goal: entries recorded and totalled.",
        "",
        "### Work packages",
        "",
        "`LDG-01` Notebook and entry model with migrations",
        "",
        "- Notebook and entry tables with the ownership constraint of `01` §2.",
        "",
        "`LDG-02` Monthly totals",
        "",
        "- Totals derived at read time (`01` §3); the pending retention card Q-002 is resolved before this package starts.",
        "",
        "### Exit criteria",
        "",
        "Both journeys of `04` §4 pass under `make test`.",
    ]),
    "N_PARALLEL": "5",
    "N_BACKLOG": "6",
    "LANES": "- service and migrations\n- tests and infrastructure",
    # specs/agent-playbook.md
    "EXCLUDED_CAPABILITIES": "sharing, a web UI, an API",
    "CONTRACT_ARTIFACTS": "shared type definitions",
    "EXAMPLE_PROMPT": "Implement LDG-01 (`07` §4): the notebook and entry tables with the ownership constraint of `01` §2. Add migration tests. Do not add totals.",
    "OWNER_CHECKPOINTS": "the first recorded entry (end of Phase 1)",
}

NOTES_RE = re.compile(r"\A<!-- TEMPLATE NOTES.*?-->\n", re.S)
COND_RE = re.compile(r"<!-- if:(?:API|UI) -->.*?<!-- /if -->", re.S)
MAKE_NOTES_RE = re.compile(r"\n#\n# TEMPLATE NOTES.*?\n\n", re.S)

def render(src, dst, extra=None):
    text = open(os.path.join(tpl, src), encoding="utf-8").read()
    text = NOTES_RE.sub("", text)
    text = COND_RE.sub("", text)
    if extra:
        text = extra(text)
    for key, value in P.items():
        text = text.replace("{{%s}}" % key, value)
    left = sorted(set(re.findall(r"\{\{[A-Z0-9_]+\}\}", text)))
    if left:
        sys.stderr.write("render: %s still carries %s\n" % (src, ", ".join(left)))
        sys.exit(2)
    os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)
    with open(dst, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)

def makefile(text):
    text = MAKE_NOTES_RE.sub("\n\n", text)
    text = re.sub(r"\{\{CONTRACT_DRIFT_TARGET\}\}: ## .*?\n\t\$\(call not_yet,\{\{CONTRACT_DRIFT_TARGET\}\},FND-01\)\n\n", "", text, flags=re.S)
    return text.replace(" {{CONTRACT_DRIFT_TARGET}}", "")

def plan(text):
    return text.replace(", {{CONTRACT_DRIFT_TARGET}},", ",")

render("Makefile", "Makefile", makefile)
render("PLAN.md", "PLAN.md")
render("GAPS.md", "GAPS.md")
render("TRACEABILITY.md", "TRACEABILITY.md")
render("CLAUDE.md", "CLAUDE.md")
render("README.md", "README.md")
render("UNLOCKS.md", "UNLOCKS.md")
render("log-README.md", ".log/README.md")
P["ROWS"] = "| `requirements.md` | %s | requirements | authoritative |" % DATE
render("docs-inputs-README.md", "docs/inputs/README.md")
render("AGENTS.md", "AGENTS.md")
render("SESSION_BOOTSTRAP_PROMPT_SAMPLE.md", "SESSION_BOOTSTRAP_PROMPT_SAMPLE.md")
render("specs/README.md", "specs/README.md")
render("specs/decision-register.md", "specs/%s-decision-register.md" % NN["REGISTER"])
P["ROWS"] = "| Dated entries with a monthly total | `01` §2–3 | MVP |"
render("specs/traceability.md", "specs/%s-traceability.md" % NN["TRACE"])
render("specs/implementation-plan.md", "specs/%s-implementation-plan.md" % NN["PLAN"], plan)
render("specs/agent-playbook.md", "specs/%s-agent-playbook.md" % NN["PLAYBOOK"])

# The raw input and the domain files: the smallest set the citations above resolve against.
open("docs/inputs/requirements.md", "w", encoding="utf-8").write(
    "# What I need\n\nA notebook for my bookkeeping. I write dated entries and want the month's total. "
    "Just me, no sharing, no website, no API. Python and PostgreSQL, because that is what I run.\n")

specs = {
    "01-scope-actors.md": """# Scope and actors

## 1. Purpose

Ledgerette records dated entries and derives monthly totals.

## 2. Actors and ownership

- There is one actor, the keeper. [input]
- An entry MUST belong to exactly one notebook, and a notebook to exactly one keeper. [input]

## 3. MVP boundary

- The MVP MUST NOT include a web UI, an API or any sharing of a notebook. [input]
- A monthly total MUST be derived from entries at read time, never stored. [input]

## 4. Success criterion

- The MVP succeeds when a keeper records a month of entries and the total equals a hand sum. [input]
""",
    "02-architecture.md": """# Architecture

## 1. Repository layout

```text
ledgerette/
  app/        the service
  tests/      the test harness
  migrations/ schema changes
```

- The service MUST be a single Python application with PostgreSQL as its only store. [input]

## 2. Topology

- One host MUST run both the service and PostgreSQL in MVP. [input]
""",
    "03-security.md": """# Security

## 1. Access

- A notebook MUST be readable and writable by its keeper only; there is no sharing in MVP. [Q-001]
- The service MUST NOT trust a client-supplied keeper identifier. [input]
""",
    "04-testing-acceptance.md": """# Testing and acceptance

## 1. Test layers

- `make test` MUST run against PostgreSQL, never a lighter substitute. [input]

## 2. Gates

- `make verify` MUST run lint, format-check, typecheck, test, build and check-docs. [input]

## 3. Fixtures

- Tests MUST create their own notebooks and never depend on shared state. [input]

## 4. Critical journeys

1. Record an entry and see it in the month's total.
2. Correct an entry; the total follows.

## 5. Release gate

- Both journeys of §4 MUST pass under `make test` before release. [input]
""",
}
for name, body in specs.items():
    open(os.path.join("specs", name), "w", encoding="utf-8", newline="\n").write(body)
PYEOF
[ $? -eq 0 ] || { printf '  FAIL  render: a template still carried a placeholder (see above)\n'; exit 1; }

# --- the log: four regime records, two cards -----------------------------------

: > .log/events.jsonl
append() { python3 scripts/log-append.py --quiet "$@" || { printf '  FAIL  seed: log-append refused %s\n' "$*"; exit 1; }; }

DATE=2026-09-08
python3 - "$tpl/decisions-seed.json" <<'PYEOF' > "$work/seed.jsonl"
import json, sys
seed = json.load(open(sys.argv[1], encoding="utf-8"))
values = {"{{DATE}}": "2026-09-08", "{{NN_TRACE}}": "05", "{{NN_REGISTER}}": "06", "{{NN_PLAN}}": "07",
          "{{REGISTER_CC_SECTION}}": "6",
          "{{D003_DECISION}}": "No non-authoritative input was received. Any mockup, competitor reference or prior draft added later receives an authority row in docs/inputs/README.md and a superseding entry before an agent may use it.",
          "{{D003_WHY}}": "an input without a declared authority level becomes a requirements source by default, silently.",
          "{{D003_ALTERNATIVES}}": "treat all inputs as authoritative (rejected: direction and requirements would blend)."}
for event in seed["events"]:
    text = json.dumps(event, ensure_ascii=False)
    for k, v in values.items():
        text = text.replace(k, v)
    assert "{{" not in text, text
    print(text)
PYEOF
while IFS= read -r line; do
    printf '%s' "$line" | append --type decision-added --payload-file -
done < "$work/seed.jsonl"

append --stream questions --type card-opened --payload-file - <<'EOF'
{"id":"Q-001","title":"Notebook sharing","surface":"security","source":"`docs/inputs/requirements.md`: \"just me, no sharing\"",
 "question":"Is a notebook ever readable by anyone but its keeper in MVP?",
 "options":["A) No → effect on security: one principal, no access model beyond ownership.",
            "B) Read-only sharing → effect on security: a second role and a grant table."],
 "recommendation":"A, because the input says so and B is a different product.","blocks":"specification"}
EOF
append --stream questions --type card-answered --set id=Q-001 --set answer=A --set date=$DATE --set recommendation_accepted=true
append --stream questions --type card-resolved --set id=Q-001
append --stream questions --type card-opened --payload-file - <<'EOF'
{"id":"Q-002","title":"Entry retention","surface":"data","source":"absent from the inputs",
 "question":"Are entries ever deleted, and after how long?",
 "options":["A) Never → effect on data: the notebook grows without bound.",
            "B) Purge after N years → effect on data: a retention period and a deletion job."],
 "recommendation":"A, because the input is silent and a purge is a decision the keeper should make.","blocks":"LDG-02"}
EOF
python3 scripts/rebuild-decisions.py --quiet
python3 scripts/rebuild-questions.py --quiet

# --- git and the hooks ----------------------------------------------------------

git init -q .
git config user.email "test@example.invalid"
git config user.name "Render Test"
git config commit.gpgsign false
install_hooks >/dev/null 2>&1

printf 'render-and-check acceptance\n'

# --- 1. the gate accepts the rendered pack ------------------------------------

if check_docs > "$work/cd1.out" 2>&1; then
    report ok "1 make check-docs exits 0 on the rendered templates" ""
else
    report no "1 make check-docs" "$(grep -E '^FAIL|Error|error' "$work/cd1.out" | head -12)"
fi

if verify_chain > "$work/vc.out" 2>&1; then
    report ok "1b make verify-chain exits 0" ""
else
    report no "1b verify-chain" "$(cat "$work/vc.out")"
fi

if grep -q 'ok   projection-fresh QUESTIONS.md' "$work/cd1.out" && grep -q 'ok   projection-fresh DECISIONS.md' "$work/cd1.out"; then
    report ok "1c both projections are fresh" ""
else
    report no "1c projection-fresh" "$(grep projection-fresh "$work/cd1.out")"
fi

# --- 2. the two rebuilds are byte-stable ---------------------------------------

python3 scripts/rebuild-decisions.py --stdout > "$work/d1"; python3 scripts/rebuild-decisions.py --stdout > "$work/d2"
python3 scripts/rebuild-questions.py --stdout > "$work/q1"; python3 scripts/rebuild-questions.py --stdout > "$work/q2"
if cmp -s "$work/d1" "$work/d2" && cmp -s "$work/d1" DECISIONS.md && cmp -s "$work/q1" "$work/q2" && cmp -s "$work/q1" QUESTIONS.md; then
    report ok "2 rebuild-decisions and rebuild-questions are byte-stable and equal the files" ""
else
    report no "2 byte stability" "a second rendering differs"
fi

# --- 3. nothing of the skill reached the pack (C4 steps 2-3) --------------------

if grep -rn '{{' . --include='*.md' --include=Makefile --exclude-dir=.git > "$work/leak1.out" 2>&1; then
    report no "3 unrendered placeholders" "$(head -3 "$work/leak1.out")"
else
    report ok "3 no {{ placeholder in any markdown file or the Makefile" ""
fi

if grep -rniE 'design-pack|template notes|CLAUDE_SKILL_DIR' . --exclude-dir=.git --exclude-dir=inputs > "$work/leak2.out" 2>&1; then
    report no "3b skill references in the pack" "$(head -3 "$work/leak2.out")"
else
    report ok "3b no reference to the skill, its notes or its directory" ""
fi

# --- 4. stage-detect walks C -> D -> frozen on this pack -----------------------

mv AGENTS.md "$work/AGENTS.md.keep"
s="$(bash "$here/scripts/stage-detect.sh" . | head -1)"
if [ "$s" = "C" ]; then report ok "4 stage-detect says C before AGENTS.md exists" ""; else report no "4 stage-detect C" "said '$s'"; fi
mv "$work/AGENTS.md.keep" AGENTS.md
s="$(bash "$here/scripts/stage-detect.sh" . | head -1)"
if [ "$s" = "D" ]; then report ok "4b stage-detect says D with AGENTS.md and a Draft spec map" ""; else report no "4b stage-detect D" "said '$s'"; fi

# --- 5. the lock layer answers (C4 step 5) --------------------------------------

git add -A
if check_locks > "$work/locks.out" 2>&1; then
    report ok "5 make check-locks exits 0 over the pack's first commit" ""
else
    report no "5 check-locks" "$(cat "$work/locks.out")"
fi
t="$(python3 scripts/lock-guard.py --tier docs/inputs/README.md | cut -f1)"
u="$(python3 scripts/lock-guard.py --tier PLAN.md | cut -f1)"
if [ "$t" = "hard-locked" ] && [ "$u" = "free" ]; then
    report ok "5b tiers: docs/inputs/README.md is hard-locked, PLAN.md is free" ""
else
    report no "5b tiers" "docs/inputs/README.md=$t PLAN.md=$u"
fi
if git commit -q -m "documentation pack" > "$work/commit.out" 2>&1; then
    report ok "5c the first commit passes the pre-commit hook" ""
else
    report no "5c first commit" "$(cat "$work/commit.out")"
fi
if [ "$(git config core.hooksPath)" = ".githooks" ]; then
    report ok "5d core.hooksPath points at .githooks" ""
else
    report no "5d hooksPath" "$(git config core.hooksPath)"
fi
# check-docs imports eventlog.py, so Python writes a __pycache__ beside it; the
# pack's .gitignore (Step C1.2) has to keep it out of the first commit.
if git ls-files | grep -q '__pycache__'; then
    report no "5e no bytecode in the pack" "a __pycache__ file is tracked: $(git ls-files | grep __pycache__ | head -1)"
else
    report ok "5e the first commit tracks no __pycache__ bytecode" ""
fi

# --- 6. the freeze (D4) on this pack -------------------------------------------

sed -i 's/^Version: 0.1-draft  $/Version: 1.0  /; s/^Status: Draft, not yet an implementation baseline  $/Status: Implementation baseline, 2026-09-08  /' specs/README.md
printf '\n# Frozen at the baseline, 2026-09-08: the contract itself.\nhard-locked: specs/**\n' >> .doc-locks
if check_docs > "$work/cd6.out" 2>&1; then
    report ok "6 check-docs still passes after the freeze stamp" ""
else
    report no "6 check-docs after freeze" "$(grep -E '^FAIL' "$work/cd6.out" | head -5)"
fi
s="$(bash "$here/scripts/stage-detect.sh" . | head -1)"
if [ "$s" = "frozen" ]; then report ok "6b stage-detect says frozen" ""; else report no "6b stage-detect frozen" "said '$s'"; fi
git add -A && git commit -q -m "freeze" >/dev/null 2>&1
t="$(python3 scripts/lock-guard.py --tier specs/01-scope-actors.md | cut -f1)"
if [ "$t" = "hard-locked" ]; then report ok "6c specs/** is hard-locked after the promotion" ""; else report no "6c specs tier" "$t"; fi

# --- 7. the suite is wired to a real gate: one broken template line fails -------

chmod u+w AGENTS.md
python3 - <<'PYEOF'
p = "AGENTS.md"
t = open(p, encoding="utf-8").read()
t = t.replace("- **Totals are derived, never stored.** A monthly total is computed from entries at read time (`01` §3).",
              "- **Totals are derived, never stored.** A monthly total is computed from entries at read time.")
open(p, "w", encoding="utf-8", newline="\n").write(t)
PYEOF
if check_docs > "$work/cd7.out" 2>&1; then
    report no "7 a red line without a § passes" "check-docs exited 0"
elif grep -q 'FAIL red-lines' "$work/cd7.out"; then
    report ok "7 a red line stripped of its § fails the gate, naming the rule" ""
else
    report no "7 red-lines" "$(grep -E '^FAIL' "$work/cd7.out")"
fi
git checkout -q -- AGENTS.md

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
