#!/bin/sh
# unlock: the ceremony that makes a change to a hard-locked file possible,
# deliberate and self-documenting. Run through `make unlock PATH=<path> REASON="..."`,
# or `make unlock PATH="<path> <path> ..." REASON="..."` for several paths that one
# reason covers: landing a package whose amendments touch three specs is one
# decision by the owner, not three.
#
# It refuses any path the manifest does not call hard-locked, appends a record per
# path to the append-only unlock log and stages it so the change and its reason
# travel in one commit, makes each file writable, and writes a single-use token
# that scripts/lock-guard.py accepts for exactly those paths. The next commit
# consumes it: .githooks/post-commit re-locks the files and deletes the token, so
# one ceremony covers one deliberate change and no more. Every path is checked
# before anything is written: one that is missing or not hard-locked refuses the
# whole ceremony and records nothing.
set -eu

targets="${1:-}"
reason="${2:-}"
log="${UNLOCK_LOG:-UNLOCKS.md}"
token="${UNLOCK_TOKEN:-.doc-unlock}"

usage() {
    echo 'usage: make unlock PATH="<path> [<path> ...]" REASON="why this change is necessary"' >&2
    exit 2
}

[ -n "$targets" ] || usage
[ -n "$reason" ] || usage
case "$reason" in *'"'*) echo 'unlock: REASON must not contain a double quote.' >&2; exit 2 ;; esac

set -f   # a path is a path, never a glob
for target in $targets; do
    [ -e "$target" ] || { echo "unlock: no such file: $target; nothing was unlocked." >&2; exit 2; }
    tier="$(python3 scripts/lock-guard.py --tier "$target" | cut -f1)"
    if [ "$tier" != "hard-locked" ]; then
        echo "unlock: $target is '$tier', not hard-locked. No ceremony is needed for it; nothing was unlocked." >&2
        exit 2
    fi
done

who="$(git config user.name 2>/dev/null || true)"
[ -n "$who" ] || who="$(id -un)"
when="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

[ -f "$log" ] || printf '# UNLOCKS\n\nOne line per ceremonial unlock of a hard-locked path.\n\n' > "$log"
for target in $targets; do
    printf -- '- unlock %s path="%s" by="%s" reason="%s"\n' "$when" "$target" "$who" "$reason" >> "$log"
done
git add -- "$log"

# Appended, not overwritten: one commit may carry several ceremonies (a spec, the
# plan and the playbook in one migration), the guard authorizes each from its
# record in UNLOCKS.md, and the token has to name every one of them or the commit
# that follows re-locks only the last. Both readers take every `path:` line.
for target in $targets; do
    chmod u+w -- "$target"
    {
        echo "path: $target"
        echo "by: $who"
        echo "date: $when"
        echo "reason: $reason"
    } >> "$token"
    echo "unlock: $target is writable for one commit."
done
echo "unlock: recorded in $log; the next commit consumes the token."
