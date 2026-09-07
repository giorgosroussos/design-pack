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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
