#!/bin/sh
# Every shell command the stage files instruct must be pre-approved by a
# `Bash(...)` pattern in SKILL.md's `allowed-tools`, or the skill stops for a
# permission prompt in the middle of a stage. This test extracts every
# backticked command from stages/*.md and SKILL.md, splits compound commands on
# `&&`, `||`, `;` and `|` (Claude Code matches each subcommand on its own), and
# matches each against the patterns with the documented glob semantics:
# `*` matches any text, a trailing ` *` also matches the bare command, and a
# pattern without `*` is an exact match. `${CLAUDE_SKILL_DIR}` is substituted
# before matching, as Claude Code does. Placeholders like <target> are replaced
# with plausible values first.
#
#   scripts/test-allowed-tools.sh
#
# Exits non-zero if any instructed command matches no pattern.
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$here" <<'PYEOF'
import fnmatch, re, sys, glob, os

here = sys.argv[1]
skill = open(os.path.join(here, "SKILL.md"), encoding="utf-8").read()
front = skill.split("---", 2)[1]
patterns = [m.group(1) for m in re.finditer(r"^\s*-\s*Bash\((.*)\)\s*$", front, re.M)]
patterns = [p.replace("${CLAUDE_SKILL_DIR}", "/skill") for p in patterns]

def matches(cmd, pat):
    if "*" not in pat:
        return cmd == pat
    if fnmatch.fnmatchcase(cmd, pat):
        return True
    return pat.endswith(" *") and cmd == pat[:-2]

def split_compound(cmd):
    """Split on &&, ||, ; and | outside quotes; Claude Code is shell-aware the same way."""
    parts, cur, quote, i = [], "", None, 0
    while i < len(cmd):
        c = cmd[i]
        if quote:
            cur += c
            if c == quote:
                quote = None
        elif c in "'\"":
            quote = c; cur += c
        elif cmd.startswith(("&&", "||"), i):
            parts.append(cur); cur = ""; i += 1
        elif c in ";|":
            parts.append(cur); cur = ""
        else:
            cur += c
        i += 1
    parts.append(cur)
    return [p.strip() for p in parts if p.strip()]

def placeholders(cmd):
    return (cmd.replace("${CLAUDE_SKILL_DIR}", "/skill").replace("<target>", "/repo")
               .replace("<scratch>", "/scratch").replace("<version>", "1.0").replace("<path>", "specs/x.md"))

sources = sorted(glob.glob(os.path.join(here, "stages", "*.md"))) + [os.path.join(here, "SKILL.md")]
commands = set()
for path in sources:
    text = open(path, encoding="utf-8").read()
    for m in re.finditer(r"`((?:cd |bash |python3 |make |git |mkdir |touch |cp |chmod |grep |xargs |find |sh )[^`]*)`", text):
        commands.add((os.path.relpath(path, here), m.group(1)))

bad, total = [], 0
for src, raw in sorted(commands):
    cmd = placeholders(raw)
    cmd = re.sub(r"\s+>\s*\S+", "", cmd)              # a redirection is not a subcommand
    for sub in split_compound(cmd):
        total += 1
        if not any(matches(sub, p) for p in patterns):
            bad.append((src, raw, sub))

print("allowed-tools acceptance")
print("  %d Bash patterns, %d instructed subcommands from %d sources" % (len(patterns), total, len(sources)))
if bad:
    for src, raw, sub in bad:
        print("  FAIL  %s: `%s` has no pattern for `%s`" % (src, raw, sub))
    print("\n%d passed, %d failed" % (total - len(bad), len(bad)))
    sys.exit(1)
print("  PASS  every instructed subcommand matches an allowed-tools pattern")
print("\n1 passed, 0 failed")
PYEOF
