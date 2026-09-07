#!/usr/bin/env python3
"""
extract-normative: list every normative statement in a spec directory with its
file, section and provenance tag.

    python3 extract-normative.py [--specs DIR] [--untagged] [--format tsv|md]

A statement is normative when it contains MUST, MUST NOT, SHALL, SHOULD,
SHOULD NOT or MAY in capitals. A lead-in line ending with `MUST:` (or another
keyword and a colon) makes every list item that follows, up to the next blank
line, normative as well. The provenance tag is the trailing `[...]` on the
statement line, or on the lead-in line for inherited items.

Tags: input | Q-NNN | D-NNN | inferred | (none)

`--untagged-as input` treats every untagged statement as `[input]`; use it only for an
adopted pack, one that `docs/inputs/README.md` declares an authoritative input in itself.

The register file (*-decision-register.md) is included: its bullets are all
normative by definition, whether or not they use a keyword.

Used by the design-pack skill after every writing round and as the input list
for the assumption hunter. Not shipped into generated repositories.
"""
import argparse
import glob
import os
import re
import sys

KEYWORD = re.compile(r"\b(MUST NOT|MUST|SHALL NOT|SHALL|SHOULD NOT|SHOULD|MAY)\b")
LEADIN = re.compile(r"\b(MUST NOT|MUST|SHALL|SHOULD|MAY)\s*:\s*$")
TAG = re.compile(r"\[((?:input|inferred|Q-\d{3}|D-\d{3})(?:[^\]]*))\]\s*$")
HEADING = re.compile(r"^(#{2,4})\s+(\d+(?:\.\d+)*)\.?\s+(.*)$")


def tag_of(line):
    m = TAG.search(line.rstrip())
    return m.group(1).split(",")[0].strip() if m else "(none)"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--specs", default="specs")
    ap.add_argument("--untagged", action="store_true", help="only statements without a provenance tag")
    ap.add_argument("--format", choices=["tsv", "md"], default="tsv")
    ap.add_argument("--untagged-as", default=None, metavar="TAG",
                    help="report untagged statements as this provenance (use `input` for an adopted pack "
                         "that docs/inputs/README.md declares authoritative)")
    args = ap.parse_args()

    rows = []
    for path in sorted(glob.glob(os.path.join(args.specs, "[0-9][0-9]-*.md"))):
        name = os.path.basename(path)
        is_register = name.endswith("-decision-register.md")
        section = "-"
        fenced = False
        inherit = None  # tag inherited from a lead-in, or None
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
        for ln, line in enumerate(lines, 1):
            if line.strip().startswith("```"):
                fenced = not fenced
                continue
            if fenced:
                continue
            hm = HEADING.match(line)
            if hm:
                section = hm.group(2)
                inherit = None
                if is_register and "change control" in hm.group(3).lower():
                    section = "change-control"
                continue
            if not line.strip():
                continue  # a blank line between a lead-in and its list is common
            is_item = bool(re.match(r"^\s*(?:[-*]|\d+\.)\s+\S", line))
            if inherit is not None and not is_item:
                inherit = None  # prose after the list ends the inheritance
            normative = bool(KEYWORD.search(line))
            if is_register and is_item and section != "change-control":
                normative = True
            if inherit is not None and is_item:
                normative = True
                tag = tag_of(line)
                if tag == "(none)":
                    tag = inherit
            else:
                tag = tag_of(line)
            if LEADIN.search(line.strip()):
                inherit = tag
            if not normative:
                continue
            if tag == "(none)" and args.untagged_as:
                tag = args.untagged_as
            if args.untagged and tag != "(none)":
                continue
            text = re.sub(r"\s+", " ", TAG.sub("", line).strip(" -*"))
            rows.append((name[:2], section, str(ln), tag, text[:160]))

    if args.format == "md":
        print("| Spec | § | Line | Provenance | Statement |")
        print("| --- | --- | --- | --- | --- |")
        for r in rows:
            print("| %s | %s | %s | %s | %s |" % (r[0], r[1], r[2], r[3], r[4].replace("|", "\\|")))
    else:
        print("spec\tsection\tline\tprovenance\tstatement")
        for r in rows:
            print("\t".join(r))
    counts = {}
    for r in rows:
        k = r[3] if not r[3].startswith(("Q-", "D-")) else r[3][:1]
        counts[k] = counts.get(k, 0) + 1
    print("# %d normative statements; by provenance: %s" % (
        len(rows), ", ".join("%s=%d" % kv for kv in sorted(counts.items()))), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
