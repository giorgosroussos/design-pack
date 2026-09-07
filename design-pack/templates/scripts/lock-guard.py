#!/usr/bin/env python3
"""
lock-guard: mechanical enforcement of the documentation lock manifest.

`check-docs.py` inspects the current state of the files. Two invariants of this
repository are not properties of a state but of a change:

  * a hard-locked file must not change at all, and
  * an append-only file must never lose a line.

Neither can be seen in a snapshot, so they are read from a unified diff, which
is what this script does. It is policy only: the hooks in `.githooks/` are
transport and contain no rules.

Usage, from the repository root:

    python3 scripts/lock-guard.py --staged          # what .githooks/pre-commit runs
    git diff OLD NEW | python3 scripts/lock-guard.py
    python3 scripts/lock-guard.py --tier specs/README.md

Manifest (`.doc-locks`), one rule per line, `tier: glob`:

    hard-locked: docs/inputs/**
    append-only: DECISIONS.md
    free: PLAN.md

The last matching rule wins, so promoting a file is a line appended at the end
and the manifest is its own history. A path matching no rule is `free`.

Rules
  hard-locked   any change to the path is a violation (content, mode, rename,
                deletion) unless the change is authorized for exactly that path.
                Creating a path that did not exist is allowed: nothing is locked
                yet, and the file is immutable from that commit onward
  append-only   any removed line is a violation; this one rule catches both
                deletions and modifications, since a modified line appears as a
                removal plus an addition. Additions are always allowed, anywhere
                in the file
  free          never a violation

Authorization for a hard-locked path comes from either of two places, both
written by `make unlock`:

  * the single-use token `.doc-unlock` (untracked, consumed by the next commit),
    which is what the local pre-commit hook sees, and
  * an unlock record added to `UNLOCKS.md` in the same diff, which is what lets
    a server-side hook authorize a push whose token it never saw.

Exit status: 0 clean, 1 on any violation, 2 on a usage or manifest error.
"""

import argparse
import os
import re
import subprocess
import sys

TIERS = ("hard-locked", "append-only", "free")
DEFAULT_MANIFEST = ".doc-locks"
DEFAULT_TOKEN = ".doc-unlock"
DEFAULT_LOG = "UNLOCKS.md"
NO_NEWLINE = r"\ No newline at end of file"
UNLOCK_RE = re.compile(r'^\s*-\s+unlock\s+\S+\s+path=(?:"([^"]*)"|(\S+))')
HEADER_RE = re.compile(r'^diff --git "?a/(.*?)"? "?b/(.*?)"?$')


class ManifestError(Exception):
    pass


# --- glob matching -----------------------------------------------------------

def translate(pattern):
    """Glob to regex. `*` and `?` do not cross `/`; `**` does."""
    out, i, n = ["^"], 0, len(pattern)
    while i < n:
        c = pattern[i]
        if c == "*":
            if pattern[i:i + 3] == "**/":
                out.append("(?:.*/)?")
                i += 3
                continue
            if pattern[i:i + 2] == "**":
                out.append(".*")
                i += 2
                continue
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(c))
        i += 1
    out.append("$")
    return re.compile("".join(out))


def load_manifest(text):
    """Parse manifest text into an ordered list of (tier, regex, glob)."""
    rules = []
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            raise ManifestError("line %d: expected `tier: glob`, got %r" % (lineno, raw))
        tier, pattern = line.split(":", 1)
        tier, pattern = tier.strip(), pattern.strip()
        if tier == "version":
            continue
        if tier not in TIERS:
            raise ManifestError("line %d: unknown tier %r, expected one of %s"
                                % (lineno, tier, ", ".join(TIERS)))
        if not pattern:
            raise ManifestError("line %d: rule has no glob" % lineno)
        rules.append((tier, translate(pattern), pattern))
    return rules


def tier_of(path, rules):
    """Last matching rule wins; unmatched paths are free."""
    tier, glob = "free", None
    for t, rx, g in rules:
        if rx.match(path):
            tier, glob = t, g
    return tier, glob


# --- diff parsing ------------------------------------------------------------

def unquote(path):
    """Undo git's C-style quoting of unusual path names."""
    if len(path) < 2 or path[0] != '"' or path[-1] != '"':
        return path
    s, out, i = path[1:-1], bytearray(), 0
    simple = {"n": 10, "t": 9, "r": 13, '"': 34, "\\": 92}
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            nxt = s[i + 1]
            if nxt in simple:
                out.append(simple[nxt])
                i += 2
                continue
            if nxt.isdigit() and i + 3 < len(s) + 1:
                try:
                    out.append(int(s[i + 1:i + 4], 8))
                    i += 4
                    continue
                except ValueError:
                    pass
        out.extend(c.encode("utf-8"))
        i += 1
    return out.decode("utf-8", "replace")


def side_path(rest):
    """Path from a `--- a/x` or `+++ b/x` line; None for /dev/null."""
    rest = rest.strip()
    if rest == "/dev/null":
        return None
    rest = unquote(rest)
    if rest.startswith(("a/", "b/")):
        rest = rest[2:]
    return rest


def new_entry(path):
    return {"path": path, "binary": False, "removed": [], "added": [],
            "new_file": False, "deleted": False, "mode_change": False}


def parse_diff(text):
    """Unified diff -> {path: entry}. Works on any diff passed as a string."""
    files, cur, in_hunk = {}, None, False
    minus = None

    def entry(path):
        if path not in files:
            files[path] = new_entry(path)
        return files[path]

    def rename(old, new):
        if old in files and old != new:
            files[new] = files.pop(old)
            files[new]["path"] = new
        return entry(new)

    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]

        if line.startswith("diff --git "):
            m = HEADER_RE.match(line)
            path = unquote(m.group(2)) if m else "?"
            cur, in_hunk, minus = entry(path), False, None
            i += 1
            continue

        if cur is not None and not in_hunk:
            if line.startswith("--- "):
                minus = side_path(line[4:])
                if minus is None:
                    cur["new_file"] = True
                i += 1
                continue
            if line.startswith("+++ "):
                plus = side_path(line[4:])
                if plus is None:
                    cur["deleted"] = True
                target = plus or minus or cur["path"]
                cur = rename(cur["path"], target)
                if minus is None:
                    cur["new_file"] = True
                if plus is None:
                    cur["deleted"] = True
                i += 1
                continue
            if line.startswith(("old mode ", "new mode ")):
                cur["mode_change"] = True
                i += 1
                continue
            if line.startswith("rename from "):
                entry(unquote(line[len("rename from "):]))["deleted"] = True
                i += 1
                continue
            if line.startswith("rename to "):
                cur = rename(cur["path"], unquote(line[len("rename to "):]))
                i += 1
                continue
            if line.startswith("Binary files ") or line.startswith("GIT binary patch"):
                cur["binary"] = True
                i += 1
                continue

        if line.startswith("@@"):
            in_hunk = True
            i += 1
            continue

        if in_hunk and cur is not None:
            if line.startswith("-"):
                # A trailing-newline fix shows the last line removed and added
                # back with the no-newline marker beside it. That is not a loss.
                window = lines[i + 1:i + 3]
                if any(w == NO_NEWLINE for w in window) and ("+" + line[1:]) in window:
                    i += 1
                    continue
                cur["removed"].append((i + 1, line[1:]))
            elif line.startswith("+"):
                cur["added"].append(line[1:])
            elif line and line[0] not in " \\":
                in_hunk = False
                continue
        i += 1

    return files


# --- policy ------------------------------------------------------------------

def authorized_from_diff(files, log_path):
    """Paths an unlock record in this very diff authorizes."""
    out = set()
    log = files.get(log_path)
    if log:
        for added in log["added"]:
            m = UNLOCK_RE.match(added)
            if m:
                out.add(m.group(1) or m.group(2))
    return out


def read_token(text):
    """Paths a `.doc-unlock` token authorizes."""
    out = set()
    for line in text.splitlines():
        if line.strip().startswith("path:"):
            value = line.split(":", 1)[1].strip()
            if value:
                out.add(value)
    return out


def check(diff_text, rules, token_paths=(), log_path=DEFAULT_LOG):
    """Pure function: (diff, manifest, token) -> list of violations.

    Each violation is (rule, path, detail).
    """
    files = parse_diff(diff_text)
    authorized = set(token_paths) | authorized_from_diff(files, log_path)
    violations = []

    for path in sorted(files):
        info = files[path]
        tier, glob = tier_of(path, rules)

        if tier == "hard-locked":
            if path in authorized:
                continue
            if info["new_file"] and not info["deleted"]:
                # Nothing is locked yet in a path that did not exist. The file
                # becomes immutable from the commit that introduces it, which is
                # also what lets the pack's own first commit through.
                continue
            what = ("deleted" if info["deleted"] else
                    "mode changed" if info["mode_change"] and not info["removed"] and not info["added"] else
                    "modified")
            violations.append((
                "hard-locked", path,
                "%s, but `%s` is hard-locked. Run `make unlock PATH=%s REASON=\"...\"` first."
                % (what, glob, path)))
            continue

        if tier == "append-only":
            if info["binary"]:
                violations.append((
                    "append-only", path,
                    "binary change to an append-only path; its lines cannot be verified"))
                continue
            for lineno, text in info["removed"]:
                violations.append((
                    "append-only", path,
                    "removes a line (%s is append-only; edit and delete both show up here, "
                    "append instead): %s" % (glob, text.strip()[:80] or "(blank line)")))

    return violations


# --- transport ---------------------------------------------------------------

def staged_diff(root):
    cmd = ["git", "diff", "--cached", "--no-color", "--no-renames", "--unified=0"]
    proc = subprocess.run(cmd, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr.decode("utf-8", "replace"))
        sys.exit(2)
    return proc.stdout.decode("utf-8", "replace")


def main():
    ap = argparse.ArgumentParser(description="Enforce the documentation lock manifest over a diff.")
    ap.add_argument("--root", default=".", help="repository root (default: current directory)")
    ap.add_argument("--staged", action="store_true", help="check the staged change instead of stdin")
    ap.add_argument("--manifest", default=None, help="manifest file (default: <root>/%s)" % DEFAULT_MANIFEST)
    ap.add_argument("--token", default=None, help="unlock token file (default: <root>/%s)" % DEFAULT_TOKEN)
    ap.add_argument("--no-token", action="store_true",
                    help="ignore any local token; a server-side hook never sees one")
    ap.add_argument("--log", default=DEFAULT_LOG, help="unlock log path inside the repository")
    ap.add_argument("--tier", metavar="PATH", help="print the tier of one path and exit")
    ap.add_argument("--quiet", action="store_true", help="print only violations")
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    manifest_path = args.manifest or os.path.join(root, DEFAULT_MANIFEST)
    if not os.path.isfile(manifest_path):
        sys.stderr.write("lock-guard: no manifest at %s\n" % manifest_path)
        return 2
    with open(manifest_path, encoding="utf-8") as fh:
        try:
            rules = load_manifest(fh.read())
        except ManifestError as exc:
            sys.stderr.write("lock-guard: %s: %s\n" % (manifest_path, exc))
            return 2

    if args.tier:
        probe = args.tier[2:] if args.tier.startswith("./") else args.tier
        tier, glob = tier_of(probe, rules)
        print("%s\t%s" % (tier, glob or "(no rule; free by default)"))
        return 0

    diff_text = staged_diff(root) if args.staged else sys.stdin.read()

    token_path = args.token or os.path.join(root, DEFAULT_TOKEN)
    token_paths = set()
    if not args.no_token and os.path.isfile(token_path):
        with open(token_path, encoding="utf-8") as fh:
            token_paths = read_token(fh.read())

    violations = check(diff_text, rules, token_paths, args.log)

    for rule, path, detail in violations:
        print("LOCK %-12s %s: %s" % (rule, path, detail))
    if violations:
        print()
        print("lock-guard: %d violation(s). Nothing was committed." % len(violations))
        return 1
    if not args.quiet:
        print("lock-guard: clean (%d rule(s) in %s)" % (len(rules), os.path.basename(manifest_path)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
