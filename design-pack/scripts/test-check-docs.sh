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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
