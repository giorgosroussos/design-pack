#!/bin/sh
# Acceptance test for the lock enforcement layer: the manifest, the guard, the
# ceremony and the hooks, exercised in a throwaway git repository seeded from the
# templates. Nothing outside the temporary directory is touched.
#
#   scripts/test-lock-guard.sh [--keep]
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

report() {  # report <status> <case> <message>
    if [ "$1" = "ok" ]; then
        pass=$((pass + 1))
        printf '  PASS  %s\n' "$2"
    else
        fail=$((fail + 1))
        printf '  FAIL  %s: %s\n' "$2" "$3"
    fi
}

cleanup() {
    if [ -n "$keep" ]; then
        printf '\nkept: %s\n' "$work"
    else
        chmod -R u+w "$work" 2>/dev/null
        rm -rf "$work"
    fi
}
trap cleanup EXIT

# --- seed ---------------------------------------------------------------------

repo="$work/repo"
mkdir -p "$repo/scripts" "$repo/githooks" "$repo/docs/inputs" "$repo/specs"
cd "$repo" || exit 2

cp "$tpl/scripts/lock-guard.py" scripts/lock-guard.py
cp "$tpl/scripts/unlock.sh" scripts/unlock.sh
cp "$tpl/.doc-locks" .doc-locks
mkdir -p .githooks
cp "$tpl/githooks/pre-commit" "$tpl/githooks/post-commit" "$tpl/githooks/pre-receive" .githooks/
rmdir githooks 2>/dev/null
sed -e 's/{{[A-Z_]*}}//g' "$tpl/Makefile" > Makefile
sed -e '1,/^-->$/d' "$tpl/UNLOCKS.md" > UNLOCKS.md
printf '.doc-unlock\n' > .gitignore

# The append-only subject is the event log. Its hash chain is not this test's
# business: lock-guard only ever counts removed lines.
mkdir -p .log
cat > .log/events.jsonl <<'EOF'
{"seq":1,"ts":"2026-09-04T09:00:00Z","actor":"agent","stream":"decisions","type":"decision-added","payload":{"id":"D-001"},"prev":"0000","hash":"aaaa"}
{"seq":2,"ts":"2026-09-04T09:01:00Z","actor":"agent","stream":"decisions","type":"decision-added","payload":{"id":"D-002"},"prev":"aaaa","hash":"bbbb"}
EOF

cat > docs/inputs/requirements.md <<'EOF'
# What we need

The raw material, exactly as the owner wrote it.
EOF

cat > PLAN.md <<'EOF'
# PLAN

## Now

### FND-01 — Command contract
EOF

git init -q .
git config user.email "test@example.invalid"
git config user.name "Lock Test"
git config commit.gpgsign false

if command -v make >/dev/null 2>&1; then
    HAVE_MAKE=1
else
    HAVE_MAKE=""
    printf '  NOTE  make is not installed; driving unlock through sh scripts/unlock.sh\n'
fi

unlock_cmd() {  # unlock_cmd <path> <reason>
    if [ -n "$HAVE_MAKE" ]; then
        make unlock PATH="$1" REASON="$2" >"$work/unlock.out" 2>&1
    else
        sh scripts/unlock.sh "$1" "$2" >"$work/unlock.out" 2>&1
    fi
}

guard() { python3 scripts/lock-guard.py --staged >"$work/guard.out" 2>&1; }

# hooks first, so the seed commit also proves the guard lets a repository be born
if [ -n "$HAVE_MAKE" ]; then
    make install-hooks >/dev/null 2>&1
else
    git config core.hooksPath .githooks
    chmod +x .githooks/pre-commit .githooks/post-commit .githooks/pre-receive
fi

git add -A
if python3 scripts/lock-guard.py --staged > "$work/nohead.out" 2>&1 && grep -q 'no HEAD yet' "$work/nohead.out"; then
    report ok "0 before the first commit the guard says nothing is locked yet, rather than a bare clean" ""
else
    report no "0 no-HEAD message" "$(cat "$work/nohead.out")"
fi
if git commit -q -m "seed" 2>"$work/seed.out"; then
    report ok "seed commit: a repository may be created under a hard-locked glob" ""
else
    report no "seed commit" "blocked: $(cat "$work/seed.out")"
fi

# mirror the Stage C chmod pass
chmod 0444 docs/inputs/requirements.md

printf '\nlock-guard acceptance\n'

# --- 1. modify an existing line in an append-only file -> blocked --------------

sed -i 's/"id":"D-002"/"id":"D-009"/' .log/events.jsonl
git add .log/events.jsonl
if guard; then
    report no "1 append-only: modifying an existing line" "guard exited 0"
elif grep -q 'events.jsonl' "$work/guard.out"; then
    report ok "1 append-only: modifying an existing line is blocked and named" ""
else
    report no "1 append-only: modifying an existing line" "did not name the file: $(cat "$work/guard.out")"
fi
git reset -q HEAD .log/events.jsonl
git checkout -- .log/events.jsonl

# --- 2. append to the same file -> allowed ------------------------------------

printf '{"seq":3,"ts":"2026-09-04T09:02:00Z","actor":"agent","stream":"decisions","type":"decision-superseded","payload":{"id":"D-001","by":"D-002"},"prev":"bbbb","hash":"cccc"}\n' >> .log/events.jsonl
git add .log/events.jsonl
if guard; then
    report ok "2 append-only: appending is allowed" ""
else
    report no "2 append-only: appending" "guard exited non-zero: $(cat "$work/guard.out")"
fi
git reset -q HEAD .log/events.jsonl
git checkout -- .log/events.jsonl

# --- 3. modify a hard-locked file with no token -> blocked --------------------

chmod u+w docs/inputs/requirements.md
printf 'A line the owner never wrote.\n' >> docs/inputs/requirements.md
git add docs/inputs/requirements.md
if guard; then
    report no "3 hard-locked: change without a token" "guard exited 0"
elif grep -q 'docs/inputs/requirements.md' "$work/guard.out"; then
    report ok "3 hard-locked: change without a token is blocked and named" ""
else
    report no "3 hard-locked: change without a token" "did not name the file: $(cat "$work/guard.out")"
fi
git reset -q HEAD docs/inputs/requirements.md
git checkout -- docs/inputs/requirements.md
chmod 0444 docs/inputs/requirements.md

# --- 3b. a layer note and a gotcha are free, beside the hard-locked inputs -----
# Both live under docs/, which is why the manifest's two globs are written not to
# overlap: the raw material is the owner's and never changes, the notes are the
# sessions' and change constantly.

mkdir -p docs/layers
printf '# FND-01 — the layer\n\n## What this package established\n\nx\n' > docs/layers/FND-01.md
printf '# Gotchas\n\nThe runner prints nothing on a fatal error unless PAO_DISABLE=1.\n' > docs/gotchas.md
chmod u+w docs/inputs/requirements.md
printf 'A line the owner never wrote.\n' >> docs/inputs/requirements.md
git add docs/layers/FND-01.md docs/gotchas.md docs/inputs/requirements.md
if guard; then
    report no "3b docs/: a write to the hard-locked inputs in the same commit" "guard exited 0"
elif grep -q 'docs/inputs/requirements.md' "$work/guard.out" \
     && ! grep -q 'docs/layers/FND-01.md' "$work/guard.out" \
     && ! grep -q 'docs/gotchas.md' "$work/guard.out"; then
    report ok "3b docs/: the layer note and the gotchas file are free; only the input is refused" ""
else
    report no "3b docs/ tiers" "$(cat "$work/guard.out")"
fi
git reset -q HEAD docs/layers/FND-01.md docs/gotchas.md docs/inputs/requirements.md
git checkout -- docs/inputs/requirements.md
chmod 0444 docs/inputs/requirements.md
git add docs/layers/FND-01.md docs/gotchas.md
if guard; then
    report ok "3c docs/: the two free paths commit on their own" ""
else
    report no "3c docs/ free paths" "$(cat "$work/guard.out")"
fi
git reset -q HEAD docs/layers/FND-01.md docs/gotchas.md
rm -rf docs/layers docs/gotchas.md

# --- 4. the ceremony: unlock, change, commit ----------------------------------

if unlock_cmd docs/inputs/requirements.md "the owner sent a corrected page"; then
    printf 'A correction the owner sent.\n' >> docs/inputs/requirements.md
    git add docs/inputs/requirements.md
    if git commit -q -m "apply the owner's correction" >"$work/commit4.out" 2>&1; then
        ok4=1
    else
        ok4=""
    fi
else
    ok4=""
    printf '  NOTE  unlock failed: %s\n' "$(cat "$work/unlock.out")"
fi

if [ -n "$ok4" ]; then
    report ok "4a ceremony: the authorized commit succeeds" ""
else
    report no "4a ceremony: the authorized commit" "$(cat "$work/commit4.out" 2>/dev/null)"
fi

if grep -q 'path="docs/inputs/requirements.md"' UNLOCKS.md; then
    report ok "4b ceremony: the unlock is recorded in UNLOCKS.md" ""
else
    report no "4b ceremony: unlock record" "no record in UNLOCKS.md"
fi

if [ -f .doc-unlock ]; then
    report no "4c ceremony: the token is single-use" "the token survived the commit"
else
    report ok "4c ceremony: the token is consumed by the commit" ""
fi

mode="$(ls -l docs/inputs/requirements.md | cut -c1-10)"
if [ "$mode" = "-r--r--r--" ]; then
    report ok "4d ceremony: the file is read-only again" ""
else
    report no "4d ceremony: re-locking" "mode is $mode, expected -r--r--r--"
fi

# a second change without a second ceremony must be blocked again
chmod u+w docs/inputs/requirements.md
printf 'And another one, unauthorized.\n' >> docs/inputs/requirements.md
git add docs/inputs/requirements.md
if guard; then
    report no "4e ceremony: one unlock covers one commit" "a second change passed"
else
    report ok "4e ceremony: one unlock covers one commit, not two" ""
fi
git reset -q HEAD docs/inputs/requirements.md
git checkout -- docs/inputs/requirements.md
chmod 0444 docs/inputs/requirements.md

# --- 4h. two ceremonies in one commit: both authorized, both re-locked --------
# A migration touches several locked files at once. The guard reads each unlock
# record from UNLOCKS.md, so all of them are authorized; the re-lock afterwards
# has to cover all of them too, or the next commit finds a writable locked file.

printf 'A second input page.\n' > docs/inputs/second.md
git add docs/inputs/second.md && git commit -q -m "add a second input page"
chmod 0444 docs/inputs/second.md
if unlock_cmd docs/inputs/requirements.md "migration: first of two" \
   && unlock_cmd docs/inputs/second.md "migration: second of two"; then
    printf 'Edited under the first ceremony.\n' >> docs/inputs/requirements.md
    printf 'Edited under the second ceremony.\n' >> docs/inputs/second.md
    git add docs/inputs/requirements.md docs/inputs/second.md
    if guard; then
        report ok "4h two ceremonies in one commit: the guard authorizes both paths" ""
    else
        report no "4h two ceremonies" "$(cat "$work/guard.out" 2>/dev/null)"
    fi
    git commit -q -m "two ceremonies, one commit" >/dev/null 2>&1
    m1="$(ls -l docs/inputs/requirements.md | cut -c1-10)"
    m2="$(ls -l docs/inputs/second.md | cut -c1-10)"
    if [ "$m1" = "-r--r--r--" ] && [ "$m2" = "-r--r--r--" ]; then
        report ok "4h2 both unlocked files are read-only again after the commit" ""
    else
        report no "4h2 re-locking after two ceremonies" "requirements=$m1 second=$m2"
    fi
else
    report no "4h two ceremonies" "$(cat "$work/unlock.out")"
fi
chmod u+w docs/inputs/requirements.md docs/inputs/second.md 2>/dev/null || true

# --- 4f. the ceremony when the commit deletes the unlocked path ---------------
# post-commit must consume the token even when there is nothing left to re-lock.

if unlock_cmd docs/inputs/requirements.md "the owner withdrew this page"; then
    git rm -q -f docs/inputs/requirements.md
    git commit -q -m "withdraw the page" >"$work/commit4f.out" 2>&1 || printf '  NOTE  4f commit: %s\n' "$(cat "$work/commit4f.out")"
fi
if [ -f .doc-unlock ]; then
    report no "4f ceremony: token consumed when the path is deleted" "the token survived the deleting commit"
else
    report ok "4f ceremony: the token is consumed even when the unlocked path is deleted" ""
fi

# bring the file back (creation under a hard-locked glob needs no ceremony) ...
git checkout -q HEAD~1 -- docs/inputs/requirements.md
git add docs/inputs/requirements.md
git commit -q -m "restore the page" >/dev/null 2>&1
chmod 0444 docs/inputs/requirements.md
# ... and prove no stale authorization is left: the next edit is blocked again.
chmod u+w docs/inputs/requirements.md
printf 'Edited after the deleting ceremony.\n' >> docs/inputs/requirements.md
git add docs/inputs/requirements.md
if guard; then
    report no "4g ceremony: no authorization survives a deleting commit" "the edit passed without a token"
else
    report ok "4g ceremony: no authorization survives a deleting commit" ""
fi
git reset -q HEAD docs/inputs/requirements.md
git checkout -- docs/inputs/requirements.md
chmod 0444 docs/inputs/requirements.md

# --- 5. --no-verify bypasses the local hook (expected; the remote closes it) ---

sed -i 's/"id":"D-001"/"id":"D-042"/' .log/events.jsonl
git add .log/events.jsonl
if git commit -q --no-verify -m "bypass" >"$work/commit5.out" 2>&1; then
    report ok "5 --no-verify bypasses the local hook, as documented" ""
else
    report no "5 --no-verify" "the local hook blocked it, which contradicts the README note"
fi

# the same change is caught server-side, where --no-verify cannot reach
git diff --no-color --no-renames --unified=0 HEAD~1 HEAD > "$work/pushed.diff"
if python3 scripts/lock-guard.py --manifest .doc-locks --no-token --quiet < "$work/pushed.diff" >"$work/prereceive.out" 2>&1; then
    report no "5b the pushed diff is rejected by the server-side check" "the guard accepted the bypassed commit"
else
    report ok "5b the bypassed commit is caught by the server-side check" ""
fi

# --- 7. the manifest may only tighten ------------------------------------------
# W3: appending a demotion is a legal append, so the guard compares the manifest
# before and after the change and refuses any path whose tier would go down.

HEAD7="$(git rev-parse HEAD)"
chmod u+w .doc-locks
printf '\nfree: docs/inputs/**\n' >> .doc-locks
chmod u+w docs/inputs/requirements.md
printf 'Edited under a self-granted demotion.\n' >> docs/inputs/requirements.md
git add .doc-locks docs/inputs/requirements.md
if guard; then
    report no "7 demotion + edit in one commit" "the guard accepted it"
elif grep -q 'LOCK demotion' "$work/guard.out" && grep -q 'docs/inputs/requirements.md' "$work/guard.out"; then
    report ok "7 a demotion appended in the same commit as the edit it enables is blocked, twice over" ""
else
    report no "7 demotion" "$(cat "$work/guard.out")"
fi
git reset -q --hard "$HEAD7"
chmod 0444 docs/inputs/requirements.md

# the two-push variant: push 1 only demotes, push 2 would use it. The server
# judges push 1 with the manifest it replaces and compares it to the one pushed.
chmod u+w .doc-locks
printf '\nfree: docs/inputs/**\n' >> .doc-locks
git add .doc-locks
git commit -q --no-verify -m "push 1: demote only" >/dev/null 2>&1
git show "$HEAD7:.doc-locks" > "$work/m.base"
git show "HEAD:.doc-locks" > "$work/m.new"
git diff --no-color --no-renames --unified=0 "$HEAD7" HEAD > "$work/push1.diff"
if python3 scripts/lock-guard.py --manifest "$work/m.base" --new-manifest "$work/m.new" --no-token --quiet < "$work/push1.diff" >"$work/pr7.out" 2>&1; then
    report no "7b a demotion-only push" "the server-side check accepted it"
elif grep -q 'LOCK demotion' "$work/pr7.out"; then
    report ok "7b a push that only demotes is rejected server-side, so no later push can use it" ""
else
    report no "7b demotion-only push" "$(cat "$work/pr7.out")"
fi
# a server that is not handed the pushed manifest fails closed rather than guessing
if python3 scripts/lock-guard.py --manifest "$work/m.base" --no-token --quiet < "$work/push1.diff" >"$work/pr7c.out" 2>&1; then
    report no "7c manifest change without --new-manifest" "accepted"
elif grep -q 'new manifest was not supplied' "$work/pr7c.out"; then
    report ok "7c a manifest change with no new manifest to compare fails closed" ""
else
    report no "7c fail closed" "$(cat "$work/pr7c.out")"
fi
git reset -q --hard "$HEAD7"
chmod 0444 docs/inputs/requirements.md

# --- 8. the lock layer guards itself -------------------------------------------

chmod u+w scripts/lock-guard.py
printf '# weakened\n' >> scripts/lock-guard.py
git add scripts/lock-guard.py
if guard; then
    report no "8 editing the guard" "passed without a ceremony"
elif grep -q 'scripts/lock-guard.py' "$work/guard.out"; then
    report ok "8 editing scripts/lock-guard.py without a ceremony is blocked" ""
else
    report no "8 guard self-protection" "$(cat "$work/guard.out")"
fi
git reset -q --hard "$HEAD7"

# a promotion is the one manifest change the pack needs; with the Stage C
# manifest it is a ceremony, and it goes through
chmod u+w .doc-locks
printf '\nhard-locked: specs/**\n' >> .doc-locks
git add .doc-locks
if guard; then
    report no "8b promotion without a ceremony" "the hard-locked manifest changed freely"
else
    report ok "8b a promotion without a ceremony is blocked: the manifest is hard-locked" ""
fi
git reset -q --hard "$HEAD7"
if unlock_cmd .doc-locks "freeze: promote specs/**"; then
    printf '\nhard-locked: specs/**\n' >> .doc-locks
    git add .doc-locks
    if git commit -q -m "freeze" >"$work/commit8c.out" 2>&1; then
        report ok "8c a promotion through make unlock is accepted (no demotion, path authorized)" ""
    else
        report no "8c promotion ceremony" "$(cat "$work/commit8c.out")"
    fi
else
    report no "8c unlock .doc-locks" "$(cat "$work/unlock.out")"
fi
chmod 0444 docs/inputs/requirements.md

# --- policy unit cases --------------------------------------------------------
# The guard is a pure function of (diff, manifest, token). These run it directly
# on crafted diffs, with no git and no filesystem in the way.

if python3 - "$tpl/scripts/lock-guard.py" <<'UNITEOF'
import importlib.util, sys

spec = importlib.util.spec_from_file_location("lg", sys.argv[1])
lg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lg)

rules = lg.load_manifest("""
version: 1
free: PLAN.md
free: DECISIONS.md
append-only: .log/events.jsonl
append-only: UNLOCKS.md
hard-locked: docs/inputs/**
hard-locked: specs/**
free: specs/README.md
""")

BASE_MANIFEST = """
version: 1
free: scripts/**
append-only: .doc-locks
hard-locked: docs/inputs/**
"""
def tiers(extra):
    return lg.load_manifest(BASE_MANIFEST + extra + "\n")
base = tiers("")
demote = lambda extra: [(o, b, a) for o, b, a, _ in lg.demotions(base, tiers(extra))]
assert demote("free: docs/inputs/**") == [("docs/inputs/**", "hard-locked", "free")], "same glob, lower tier"
assert demote("free: docs/**") == [("docs/inputs/**", "hard-locked", "free")], "a broader glob over a locked one"
assert demote("free: docs/inputs/req.md") == [("docs/inputs/**", "hard-locked", "free")], "a narrower glob carved out"
assert demote("append-only: docs/inputs/**") == [("docs/inputs/**", "hard-locked", "append-only")], "one step down is still down"
assert demote("hard-locked: specs/**") == [], "a promotion of a free path is not a demotion"
assert demote("hard-locked: .doc-locks") == [], "tightening the manifest itself is not a demotion"
assert demote("free: scripts/**") == [], "re-declaring the same tier is not a demotion"

MANIFEST_APPEND = """
diff --git a/.doc-locks b/.doc-locks
--- a/.doc-locks
+++ b/.doc-locks
@@ -4,0 +5 @@
+hard-locked: specs/**
"""
# with an append-only manifest (an older pack), a promotion is an ordinary append
assert lg.check(MANIFEST_APPEND, base, new_rules=tiers("hard-locked: specs/**")) == [], "promotion under an append-only manifest needs no ceremony"
v = lg.check(MANIFEST_APPEND.replace("hard-locked: specs/**", "free: docs/inputs/**"), base, new_rules=tiers("free: docs/inputs/**"))
assert [x[0] for x in v] == ["demotion"], "a demotion appended to an append-only manifest is exactly one violation: %r" % v
v = lg.check(MANIFEST_APPEND, base)
assert [x[0] for x in v] == ["demotion"] and "not supplied" in v[0][2], "no new manifest -> fail closed: %r" % v

MODIFY_INPUT = """
diff --git a/docs/inputs/req.md b/docs/inputs/req.md
--- a/docs/inputs/req.md
+++ b/docs/inputs/req.md
@@ -1 +1 @@
-owner text
+agent text
"""

RECORD = '- unlock 2026-09-04T10:00:00Z path="%s" by="o" reason="r"'

def log_diff(path):
    return """
diff --git a/UNLOCKS.md b/UNLOCKS.md
--- a/UNLOCKS.md
+++ b/UNLOCKS.md
@@ -9,0 +10 @@
+""" + RECORD % path + "\n"

cases = [
    ("append-only, modified line", """
diff --git a/.log/events.jsonl b/.log/events.jsonl
--- a/.log/events.jsonl
+++ b/.log/events.jsonl
@@ -2 +2 @@
-{"seq":2,"payload":{"id":"D-002"},"hash":"bbbb"}
+{"seq":2,"payload":{"id":"D-009"},"hash":"bbbb"}
""", (), 1),
    ("append-only, addition mid-file", """
diff --git a/.log/events.jsonl b/.log/events.jsonl
--- a/.log/events.jsonl
+++ b/.log/events.jsonl
@@ -2,0 +3 @@
+{"seq":3,"payload":{"id":"D-003"},"hash":"cccc"}
""", (), 0),
    ("append-only, file deleted", """
diff --git a/.log/events.jsonl b/.log/events.jsonl
deleted file mode 100644
--- a/.log/events.jsonl
+++ /dev/null
@@ -1,2 +0,0 @@
-{"seq":1,"hash":"aaaa"}
-{"seq":2,"hash":"bbbb"}
""", (), 2),
    ("hard-locked, unauthorized", MODIFY_INPUT, (), 1),
    ("hard-locked, token", MODIFY_INPUT, ("docs/inputs/req.md",), 0),
    ("hard-locked, record in the same diff", log_diff("docs/inputs/req.md") + MODIFY_INPUT, (), 0),
    ("hard-locked, record for another path", log_diff("specs/03-domain-model.md") + MODIFY_INPUT, (), 1),
    ("hard-locked, renamed away", """
diff --git a/docs/inputs/req.md b/docs/inputs/req.md
deleted file mode 100644
--- a/docs/inputs/req.md
+++ /dev/null
@@ -1 +0,0 @@
-owner text
diff --git a/docs/other.md b/docs/other.md
new file mode 100644
--- /dev/null
+++ b/docs/other.md
@@ -0,0 +1 @@
+owner text
""", (), 1),
    ("last matching rule wins", """
diff --git a/specs/README.md b/specs/README.md
--- a/specs/README.md
+++ b/specs/README.md
@@ -1 +1 @@
-Status: Draft
+Status: Implementation baseline
""", (), 0),
    ("trailing-newline fix is not a removal", """
diff --git a/.log/events.jsonl b/.log/events.jsonl
--- a/.log/events.jsonl
+++ b/.log/events.jsonl
@@ -2 +2,2 @@
-{"seq":2,"hash":"bbbb"}
\\ No newline at end of file
+{"seq":2,"hash":"bbbb"}
+{"seq":3,"hash":"cccc"}
""", (), 0),
    ("a NEW binary file under a hard-locked glob is an addition, not a change", """
diff --git a/docs/inputs/mockups/board.zip b/docs/inputs/mockups/board.zip
new file mode 100644
index 0000000..23f5aa5
Binary files /dev/null and b/docs/inputs/mockups/board.zip differ
""", (), 0),
    ("a CHANGED binary file under a hard-locked glob still needs the ceremony", """
diff --git a/docs/inputs/mockups/board.zip b/docs/inputs/mockups/board.zip
index 23f5aa5..91b2c0d 100644
Binary files a/docs/inputs/mockups/board.zip and b/docs/inputs/mockups/board.zip differ
""", (), 1),
    ("a new text file under a hard-locked glob, from the extended header alone", """
diff --git a/docs/inputs/requirements/brief.md b/docs/inputs/requirements/brief.md
new file mode 100644
index 0000000..1234567
--- /dev/null
+++ b/docs/inputs/requirements/brief.md
@@ -0,0 +1 @@
+What I need.
""", (), 0),
    ("free path, rewritten wholesale", """
diff --git a/PLAN.md b/PLAN.md
--- a/PLAN.md
+++ b/PLAN.md
@@ -1,3 +1 @@
-a
-b
-c
+d
""", (), 0),
]

bad = []
for name, diff, token, expected in cases:
    got = len(lg.check(diff.lstrip("\n"), rules, token))
    if got != expected:
        bad.append("%s: expected %d, got %d" % (name, expected, got))

for b in bad:
    print(b)
sys.exit(1 if bad else 0)
UNITEOF
then
    report ok "6 policy unit cases over crafted diffs (24 cases)" ""
else
    report no "6 policy unit cases" "see the lines above"
fi

# --- 9. --relock: the mode bits follow the manifest ----------------------------

chmod u+w docs/inputs/requirements.md scripts/lock-guard.py .doc-locks 2>/dev/null
printf 'x\n' > docs/inputs/extra.md
n="$(python3 scripts/lock-guard.py --relock --quiet; python3 scripts/lock-guard.py --relock | sed 's/[^0-9]//g')"
m1="$(ls -l docs/inputs/requirements.md | cut -c1-10)"; m2="$(ls -l docs/inputs/extra.md | cut -c1-10)"
m3="$(ls -l scripts/lock-guard.py | cut -c1-10)"; m4="$(ls -l PLAN.md | cut -c1-10)"
m5="$(ls -l .githooks/pre-commit | cut -c1-10)"
case "$m1$m2$m3" in *w*) ro="" ;; *) ro=1 ;; esac
case "$m4" in *w*) freeok=1 ;; *) freeok="" ;; esac
case "$m5" in -r-x*) hookok=1 ;; *) hookok="" ;; esac
if [ -n "$ro" ] && [ -n "$freeok" ] && [ -n "$hookok" ]; then
    report ok "9 --relock strips the write bits of every hard-locked file (tracked or not), keeps the hooks executable, leaves free files alone ($n files)" ""
else
    report no "9 --relock" "requirements=$m1 extra=$m2 guard=$m3 PLAN=$m4 pre-commit=$m5"
fi
rm -f docs/inputs/extra.md

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
