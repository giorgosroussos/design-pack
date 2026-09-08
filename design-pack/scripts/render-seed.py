#!/usr/bin/env python3
"""
render-seed: render the regime records of `templates/decisions-seed.json` and
append them to a target's event log, in order, through `log-append.py`.

    python3 render-seed.py --root <target> \
        --set DATE=2026-09-08 --set NN_TRACE=05 --set NN_REGISTER=06 --set NN_PLAN=07 \
        --set NN_PLAYBOOK=08 --set REGISTER_CC_SECTION=6 \
        --set D003_DECISION="..." --set D003_WHY="..." --set D003_ALTERNATIVES="..."

    python3 render-seed.py --set ... --stdout      # print the rendered payloads, append nothing

Every `{{NAME}}` in the seed must have a `--set NAME=value`; a placeholder left
unrendered is refused before anything is appended, and named. The seed's `notes`
say how D-003 reads with and without non-authoritative inputs. Stage B round B2
and Stage C (adopted packs) are the callers; the skill's `allowed-tools` covers
this script, which is the point: rendering the seed used to be an improvised
command no pattern matched.

Exit status: 0 appended (or printed), 2 usage or an unrendered placeholder, or
the exit status of the first `log-append.py` that refused a record.
"""
import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
DEFAULT_SEED = os.path.join(SKILL, "templates", "decisions-seed.json")
LOG_APPEND = os.path.join(SKILL, "templates", "scripts", "log-append.py")
PLACEHOLDER_RE = re.compile(r"\{\{([A-Z0-9_]+)\}\}")


def main():
    ap = argparse.ArgumentParser(description="Render decisions-seed.json and append its records.")
    ap.add_argument("--root", default=".", help="target repository root (default: current directory)")
    ap.add_argument("--seed", default=DEFAULT_SEED, help="seed file (default: the skill's)")
    ap.add_argument("--set", action="append", default=[], metavar="NAME=VALUE",
                    help="value for a {{NAME}} placeholder; repeatable")
    ap.add_argument("--ts", default=None, help="ISO-8601 UTC timestamp passed to log-append (default: now)")
    ap.add_argument("--stdout", action="store_true", help="print the rendered payloads, one per line; append nothing")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    values = {}
    for pair in args.set:
        if "=" not in pair:
            sys.stderr.write("render-seed: --set wants NAME=VALUE, got %r\n" % pair)
            return 2
        name, value = pair.split("=", 1)
        values[name] = value

    with open(args.seed, encoding="utf-8") as fh:
        seed = json.load(fh)

    rendered = []
    for event in seed["events"]:
        text = json.dumps(event, ensure_ascii=False)
        for name, value in values.items():
            text = text.replace("{{%s}}" % name, json.dumps(value, ensure_ascii=False)[1:-1])
        left = sorted(set(PLACEHOLDER_RE.findall(text)))
        if left:
            sys.stderr.write("render-seed: %s still carries %s; pass --set for each\n"
                             % (event.get("id", "?"), ", ".join("{{%s}}" % n for n in left)))
            return 2
        rendered.append(text)

    if args.stdout:
        for text in rendered:
            print(text)
        return 0

    for text in rendered:
        cmd = [sys.executable, LOG_APPEND, "--root", args.root, "--type", "decision-added", "--payload-file", "-"]
        if args.ts:
            cmd += ["--ts", args.ts]
        if args.quiet:
            cmd.append("--quiet")
        proc = subprocess.run(cmd, input=text.encode("utf-8"))
        if proc.returncode != 0:
            sys.stderr.write("render-seed: log-append refused %s; stopping, nothing after it was appended\n"
                             % json.loads(text)["id"])
            return proc.returncode
    if not args.quiet:
        print("render-seed: appended %d regime record(s) to %s" % (len(rendered), os.path.join(args.root, ".log", "events.jsonl")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
