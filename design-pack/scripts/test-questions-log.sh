#!/bin/sh
# Acceptance test for the questions stream and its projection: cards opened,
# answered, deferred, resolved and superseded as events, the sections that follow
# from them, and the provenance seam a superseded card used to leave open.
# Runs in a throwaway directory.
#
#   scripts/test-questions-log.sh [--keep]
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
for f in eventlog.py log-append.py verify-chain.py rebuild-decisions.py rebuild-questions.py check-docs.py; do
    cp "$tpl/scripts/$f" "scripts/$f"
done

# The rules under test, in a fresh process each time.
cat > probe.py <<'PROBEEOF'
import glob
import importlib.util
import os
import sys

spec = importlib.util.spec_from_file_location("checkdocs", "scripts/check-docs.py")
checkdocs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checkdocs)
root = os.path.abspath(".")
docs = [os.path.join(root, d) for d in checkdocs.ROOT_DOCS if os.path.isfile(os.path.join(root, d))]
docs += sorted(glob.glob(os.path.join(root, "specs", "[0-9][0-9]-*.md")))
cards, resolved, superseded = checkdocs.parse_cards(root)
checkdocs.check_cards(cards)
checkdocs.check_log(root)
checkdocs.check_provenance(root, docs, cards, resolved, set(), superseded)
for line in checkdocs.failures:
    print(line)
sys.exit(1 if checkdocs.failures else 0)
PROBEEOF

card() { python3 scripts/log-append.py --quiet --stream questions --type "$1" --payload-file -; }
event() { python3 scripts/log-append.py --quiet --stream questions "$@"; }
rebuild() { python3 scripts/rebuild-questions.py --quiet; }

printf 'questions log acceptance\n'

# --- 1. two cards opened ------------------------------------------------------

card card-opened <<'EOF'
{"id":"Q-001","title":"Vehicle identity","surface":"data",
 "source":"\"the full history of a vehicle, even if the owner changes\"",
 "question":"What identifies a vehicle for the purpose of its permanent history?",
 "options":["A) The plate is the identity → effect on data: history hangs on a string that changes.",
            "B) An internal identifier → effect on data: a merge action joins the duplicates."],
 "recommendation":"B, because the plate is not stable over the years the requirements care about.",
 "blocks":"specification"}
EOF
card card-opened <<'EOF'
{"id":"Q-002","title":"Owner reporting depth","surface":"scope",
 "source":"\"a simple view of how many jobs per week per shop\"",
 "question":"How far does the owners' view go in release 1?",
 "options":["A) One fixed page → effect on scope: one screen and one query.",
            "B) Filters and export → effect on scope: a reporting feature with its own weight."],
 "recommendation":"A, because the requirement says simple view.",
 "blocks":"phase 3"}
EOF
rebuild

if python3 - <<'EOF'
import re
text = open("QUESTIONS.md", encoding="utf-8").read()
blocking = re.search(r"^## Blocking$(.*?)^## Open$", text, re.M | re.S).group(1)
opensec = re.search(r"^## Open$(.*?)^## Resolved$", text, re.M | re.S).group(1)
assert "### Q-001 — Vehicle identity" in blocking, "Q-001 is not under Blocking"
assert "### Q-002" in opensec, "Q-002 is not under Open"
assert "- Q-001 — Vehicle identity — data — Blocking" in text, "index line for Q-001 is wrong"
assert "- Q-002 — Owner reporting depth — scope — Open" in text, "index line for Q-002 is wrong"
assert "None." in re.search(r"^## Resolved$(.*)\Z", text, re.M | re.S).group(1), "Resolved not empty"
EOF
then
    report ok "1 two cards render in the sections their blocks imply, with index lines" ""
else
    report no "1 sections and index" "the projection placed a card wrongly"
fi

if python3 probe.py > "$work/p1.out" 2>&1; then
    report ok "1b the projection passes the cards rule and projection-fresh" ""
else
    report no "1b check rules" "$(cat "$work/p1.out")"
fi

python3 scripts/rebuild-questions.py --stdout > "$work/r1"
python3 scripts/rebuild-questions.py --stdout > "$work/r2"
if cmp -s "$work/r1" "$work/r2" && cmp -s "$work/r1" QUESTIONS.md; then
    report ok "1c the rebuild is byte-identical across runs and equals the file" ""
else
    report no "1c determinism" "two renderings of one log differ"
fi

# stage-detect reads the projection: an unanswered blocking card must still stop the stage
detected="$(bash "$here/scripts/stage-detect.sh" . | head -1)"
if [ "$detected" = "A-cards" ]; then
    report ok "1d stage-detect still reads the projection and reports A-cards" ""
else
    report no "1d stage-detect" "reported '$detected', expected A-cards"
fi

# --- 2. an answer, with the recommendation accepted ---------------------------

event --type card-answered --set id=Q-001 --set answer=B --set date=2026-09-04 \
    --set recommendation_accepted=true
rebuild
if grep -q '^- Answer: B (2026-09-04; recommendation accepted)$' QUESTIONS.md; then
    report ok "2 the answer renders in the recorded form" ""
else
    report no "2 answer rendering" "$(grep -n 'Answer' QUESTIONS.md || echo 'no answer line')"
fi

# --- 3. deferral moves a card without editing one -----------------------------

event --type card-deferred --set id=Q-001 --set blocks=FND-02
rebuild
if python3 - <<'EOF'
import re
text = open("QUESTIONS.md", encoding="utf-8").read()
opensec = re.search(r"^## Open$(.*?)^## Resolved$", text, re.M | re.S).group(1)
assert "### Q-001" in opensec, "Q-001 did not move to Open"
assert "- Blocks: FND-02" in opensec, "the new Blocks value is not rendered"
assert "None. Phase 0 can proceed." in re.search(r"^## Blocking$(.*?)^## Open$", text, re.M | re.S).group(1)
EOF
then
    report ok "3 a deferral moves the card to Open and empties Blocking" ""
else
    report no "3 deferral" "the movement did not project"
fi
event --type card-reactivated --set id=Q-001 >/dev/null 2>&1
rebuild
if grep -q '^- Blocks: specification$' QUESTIONS.md; then
    report ok "3b reactivation puts it back under Blocking" ""
else
    report no "3b reactivation" "the card did not return"
fi

# --- 4. resolution requires a citation ----------------------------------------

event --type card-resolved --set id=Q-001
rebuild
if python3 probe.py > "$work/p4.out" 2>&1; then
    report no "4 a Resolved card that nothing cites" "provenance did not complain"
elif grep -q 'Q-001 is Resolved but no spec statement' "$work/p4.out"; then
    report ok "4 a Resolved card that nothing cites fails provenance" ""
else
    report no "4 provenance" "$(cat "$work/p4.out")"
fi

cat > specs/03-domain-model.md <<'EOF'
# Domain model

## 1. Vehicle

A vehicle MUST be identified by an internal identifier, with the plate as a correctable attribute. [Q-001]
EOF
if python3 probe.py > "$work/p4b.out" 2>&1; then
    report ok "4b the citation satisfies provenance" ""
else
    report no "4b provenance with a citation" "$(cat "$work/p4b.out")"
fi

# --- 5. the supersession seam -------------------------------------------------

card card-opened <<'EOF'
{"id":"Q-003","title":"Vehicle identity, second answer","surface":"data",
 "source":"Q-001; the owner changed their mind after the first workshop visit",
 "question":"Is the vehicle identified by its VIN after all?",
 "options":["A) Keep the internal identifier → effect on data: the merge action stays.",
            "B) The VIN is the identity → effect on data: the VIN becomes required at first visit."],
 "recommendation":"B, because the owner now records the VIN at the counter anyway.",
 "blocks":"specification"}
EOF
event --type card-answered --set id=Q-003 --set answer=B --set date=2026-09-05
event --type card-superseded --set id=Q-001 --set by=Q-003
event --type card-resolved --set id=Q-003
rebuild
sed -i 's/\[Q-001\]/[Q-003]/' specs/03-domain-model.md

if grep -q '^- Superseded by: Q-003$' QUESTIONS.md &&
   grep -q '^- Q-001 — Vehicle identity — data — Resolved — superseded by Q-003$' QUESTIONS.md &&
   grep -q '^- Answer: B (2026-09-04; recommendation accepted)$' QUESTIONS.md; then
    report ok "5 the superseded card stays Resolved, keeps its answer, and names its successor" ""
else
    report no "5 supersession rendering" "$(grep -n 'Superseded\|Q-001 —' QUESTIONS.md || true)"
fi

if python3 probe.py > "$work/p5.out" 2>&1; then
    report ok "5b provenance passes: the citation moved to the successor" ""
else
    report no "5b the supersession seam" "$(cat "$work/p5.out")"
fi

# the other side of the seam: a successor that does not exist must fail
event --type card-superseded --set id=Q-002 --set by=Q-004 >/dev/null 2>&1
event --type card-resolved --set id=Q-002
rebuild
if python3 probe.py > "$work/p5c.out" 2>&1; then
    report no "5c supersession by a card that does not exist" "provenance did not complain"
elif grep -q 'superseded by Q-004, which has no card' "$work/p5c.out"; then
    report ok "5c a successor that does not exist fails provenance" ""
else
    report no "5c missing successor" "$(cat "$work/p5c.out")"
fi

card card-opened <<'EOF'
{"id":"Q-004","title":"Owner reporting depth, reopened","surface":"scope",
 "source":"Q-002; the owners asked for the numbers per mechanic after all",
 "question":"Do the owners get per-mechanic numbers in release 1?",
 "options":["A) No → effect on scope: one screen, as before.",
            "B) Yes → effect on scope: per-mechanic figures and what they get used for."],
 "recommendation":"A, because nobody has said what the number would be used for.",
 "blocks":"phase 3"}
EOF
rebuild
if python3 probe.py > "$work/p5d.out" 2>&1; then
    report ok "5d opening the successor closes the seam again" ""
else
    report no "5d seam closed" "$(cat "$work/p5d.out")"
fi

# --- 6. both streams share one chain ------------------------------------------

python3 scripts/log-append.py --quiet --type decision-added --set id=D-001 --set date=2026-09-04 \
    --set title="Repository documentation regime" --set type=implementation \
    --set decision="AGENTS.md is the entry point." --set why="One file." \
    --set alternatives="docs/ (rejected)." --set affected_specs="none."
python3 scripts/rebuild-decisions.py --quiet

if python3 scripts/verify-chain.py --quiet; then
    report ok "6 verify-chain covers the whole file, both streams in one chain" ""
else
    report no "6 verify-chain across streams" "the chain did not verify"
fi

if python3 - <<'EOF'
import json
records = [json.loads(l) for l in open(".log/events.jsonl", encoding="utf-8")]
streams = sorted(set(r["stream"] for r in records))
assert streams == ["decisions", "questions"], streams
assert [r["seq"] for r in records] == list(range(1, len(records) + 1)), "seqs not contiguous"
EOF
then
    report ok "6b one file holds both streams with one contiguous sequence" ""
else
    report no "6b interleaved streams" "the sequence or the streams are wrong"
fi

python3 scripts/rebuild-questions.py --check --quiet || report no "6c questions projection" "drifted"
python3 scripts/rebuild-decisions.py --check --quiet || report no "6c decisions projection" "drifted"

# a questions event cannot be projected by the decisions renderer and vice versa
if python3 - <<'EOF'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("el", "scripts/eventlog.py")
el = importlib.util.module_from_spec(spec); spec.loader.exec_module(el)
records = [json.loads(l) for l in open(".log/events.jsonl", encoding="utf-8")]
assert len(el.project_decisions(records)) == 1, "the decisions projection saw a card"
assert len(el.project_questions(records)) == 4, "the questions projection saw a decision"
EOF
then
    report ok "6d each projection ignores the other stream's events" ""
else
    report no "6d stream isolation" "a projection folded the wrong events"
fi

# --- 7. a hand edit of the projection -----------------------------------------

printf '\n### Q-777 — A card nobody asked\n- Surface: data\n' >> QUESTIONS.md
if python3 probe.py > "$work/p7.out" 2>&1; then
    report no "7 projection-fresh on a hand-edited QUESTIONS.md" "no failure reported"
elif grep -q 'projection-fresh QUESTIONS.md' "$work/p7.out"; then
    report ok "7 projection-fresh fails on a hand-edited card" ""
else
    report no "7 projection-fresh" "$(cat "$work/p7.out")"
fi
rebuild
if python3 probe.py > "$work/p7b.out" 2>&1; then
    report ok "7b a rebuild restores it and the checks pass again" ""
else
    report no "7b rebuild" "$(cat "$work/p7b.out")"
fi

# --- 8. events the log refuses ------------------------------------------------

refuses() {  # refuses <label> <event args...>
    label="$1"; shift
    if python3 scripts/log-append.py --quiet --stream questions "$@" >"$work/refuse.out" 2>&1; then
        report no "8 $label" "the log accepted it"
    else
        report ok "8 $label is refused" ""
    fi
}
refuses "a card with an unknown surface" --type card-opened \
    --set id=Q-010 --set title=x --set surface=vibes --set source=y --set question=z \
    --set 'options=A) one → effect on data: x.' --set blocks=specification
refuses "a deferral that still blocks the specification" --type card-deferred \
    --set id=Q-002 --set blocks=specification
refuses "an event for a card that was never opened" --type card-answered \
    --set id=Q-404 --set answer=A --set date=2026-09-04
refuses "a card opened twice" --type card-opened \
    --set id=Q-001 --set title=x --set surface=data --set source=y --set question=z \
    --set 'options=A) one → effect on data: x.
B) two → effect on data: y.' --set blocks=specification
refuses "a card whose ID skips ahead (Q-010 when Q-005 is next)" --type card-opened \
    --set id=Q-010 --set title=x --set surface=data --set source=y --set question=z \
    --set 'options=A) one → effect on data: x.
B) two → effect on data: y.' --set blocks=specification
grep -q 'breaks the sequence' "$work/refuse.out" || report no "8 gap refusal reason" "$(cat "$work/refuse.out")"
if python3 scripts/rebuild-questions.py --check --quiet >/dev/null 2>&1; then
    report ok "8b the log is unchanged by the refusals" ""
else
    report no "8b refusal side effects" "a refused event reached the log"
fi

# --- 9. interleaving in the shared log ----------------------------------------
# The two streams share one file and one sequence. A projection must depend only
# on its own records, never on where they sit in that sequence. Proof: build the
# same events interleaved and separated, and compare the renderings byte for
# byte. The timestamp is pinned to the same value everywhere, so interleaving is
# the only variable that changes.

TS=2026-09-04T10:00:00Z

mk_repo() {
    mkdir -p "$1/scripts"
    for f in eventlog.py log-append.py rebuild-decisions.py rebuild-questions.py verify-chain.py; do
        cp "$tpl/scripts/$f" "$1/scripts/$f"
    done
}

dec_one() { ( cd "$1" && python3 scripts/log-append.py --quiet --ts "$TS" --type decision-added \
    --set id=D-001 --set date=2026-09-04 --set title="Repository documentation regime" \
    --set type=implementation --set decision="AGENTS.md is the entry point." \
    --set why="One file, impossible to miss." --set alternatives="docs/ (rejected)." \
    --set affected_specs="none." ); }

dec_two() { ( cd "$1" && python3 scripts/log-append.py --quiet --ts "$TS" --type decision-added \
    --set id=D-002 --set date=2026-09-04 --set title="API base path" \
    --set type=implementation --set decision="The base path is /api/v1." \
    --set why="Versioning from the first endpoint." --set alternatives="Unversioned (rejected)." \
    --set affected_specs="09 §1." ); }

card_one() { ( cd "$1" && python3 scripts/log-append.py --quiet --ts "$TS" --stream questions \
    --type card-opened --payload-file - <<'EOF'
{"id":"Q-001","title":"Vehicle identity","surface":"data","source":"the requirements",
 "question":"What identifies a vehicle?",
 "options":["A) The plate → effect on data: history hangs on a changing string.",
            "B) An internal identifier → effect on data: a merge action joins duplicates."],
 "recommendation":"B, because the plate is not stable.","blocks":"specification"}
EOF
    ); }

card_two() { ( cd "$1" && python3 scripts/log-append.py --quiet --ts "$TS" --stream questions \
    --type card-answered --set id=Q-001 --set answer=B --set date=2026-09-04 \
    --set recommendation_accepted=true ); }

woven="$work/woven"; only_dec="$work/only-dec"; only_q="$work/only-q"
mk_repo "$woven"; mk_repo "$only_dec"; mk_repo "$only_q"

dec_one  "$woven"; card_one "$woven"; dec_two  "$woven"; card_two "$woven"
dec_one  "$only_dec"; dec_two "$only_dec"
card_one "$only_q";   card_two "$only_q"

if python3 - "$woven" <<'EOF'
import json, sys
records = [json.loads(l) for l in open(sys.argv[1] + "/.log/events.jsonl", encoding="utf-8")]
assert [r["stream"] for r in records] == ["decisions", "questions", "decisions", "questions"], \
    "the woven log is not interleaved"
assert [r["seq"] for r in records] == [1, 2, 3, 4], "seqs are not contiguous"
EOF
then
    report ok "9 the woven log really interleaves the two streams (dec, q, dec, q)" ""
else
    report no "9 the woven fixture" "the log is not interleaved as the test assumes"
fi

( cd "$woven" && python3 scripts/rebuild-decisions.py --stdout ) > "$work/w-dec.md"
( cd "$woven" && python3 scripts/rebuild-questions.py --stdout ) > "$work/w-q.md"
( cd "$only_dec" && python3 scripts/rebuild-decisions.py --stdout ) > "$work/s-dec.md"
( cd "$only_q" && python3 scripts/rebuild-questions.py --stdout ) > "$work/s-q.md"

if cmp -s "$work/w-dec.md" "$work/s-dec.md"; then
    report ok "9b decisions render identically whether or not cards sit between them" ""
else
    report no "9b decisions under interleaving" "$(diff "$work/s-dec.md" "$work/w-dec.md" | head -5)"
fi

if cmp -s "$work/w-q.md" "$work/s-q.md"; then
    report ok "9c questions render identically whether or not decisions sit between them" ""
else
    report no "9c questions under interleaving" "$(diff "$work/s-q.md" "$work/w-q.md" | head -5)"
fi

# the records carry different seq values in the two logs, which is the point:
# the rendering above is identical while the chain underneath is not.
if ( cd "$woven" && python3 scripts/verify-chain.py --quiet ) &&
   ! cmp -s "$woven/.log/events.jsonl" "$only_dec/.log/events.jsonl"; then
    report ok "9d the woven chain verifies although its records differ from the separated one" ""
else
    report no "9d chain under interleaving" "the woven chain is broken or the fixtures are identical"
fi

# --- 10. stage-detect reads the projection, not the log -----------------------
# What the machine decides the stage from has to be what a person can see. An
# event that has not been rendered yet must not move the stage.

before="$(bash "$here/scripts/stage-detect.sh" . | head -1)"
card card-opened <<'EOF'
{"id":"Q-005","title":"An unrendered blocking card","surface":"security",
 "source":"appended but deliberately not rebuilt",
 "question":"Does an unrendered event move the stage?",
 "options":["A) It does → effect on security: the gate reacts to what nobody can read.",
            "B) It does not → effect on security: the machine and the reader see one state."],
 "recommendation":"B, because the projection is what a person reviews.",
 "blocks":"specification"}
EOF
during="$(bash "$here/scripts/stage-detect.sh" . | head -1)"
if [ "$during" = "$before" ]; then
    report ok "10 an appended but unrendered card does not move stage-detect (was $before)" ""
else
    report no "10 stage-detect reads the log" "verdict moved from $before to $during before any rebuild"
fi

rebuild
after="$(bash "$here/scripts/stage-detect.sh" . | head -1)"
if [ "$after" = "A-cards" ] && [ "$after" != "$before" ]; then
    report ok "10b after the rebuild the same card does move it, to A-cards" ""
else
    report no "10b stage-detect after rebuild" "reported '$after', expected A-cards (was $before)"
fi

if grep -qE '\.log|events\.jsonl' "$here/scripts/stage-detect.sh"; then
    report no "10c stage-detect names the log" "it reads something other than the projection"
else
    report ok "10c stage-detect never names the log; it reads QUESTIONS.md" ""
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
