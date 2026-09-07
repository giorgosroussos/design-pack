#!/usr/bin/env python3
"""
extract-normative: list every normative statement in a spec directory with its
file, section and provenance tag.

    python3 extract-normative.py [--specs DIR] [--untagged] [--untagged-as TAG] [--format tsv|md]

A statement is normative when it contains MUST, MUST NOT, SHALL, SHALL NOT,
SHOULD, SHOULD NOT or MAY in capitals outside a code span. A lead-in line ending
with `MUST:` (or another keyword and a colon) makes every list item that follows,
up to the next blank line, normative as well. The provenance tag is the trailing
`[...]` on the statement line, or on the lead-in line for inherited items.

Tags: input | Q-NNN | D-NNN | inferred | (none)

`--untagged-as input` treats every untagged statement as `[input]`; use it only for an
adopted pack, one that `docs/inputs/README.md` declares an authoritative input in itself.

The register file (*-decision-register.md) is included: its bullets are all
normative by definition, whether or not they use a keyword.

The detector itself lives in `templates/scripts/check-docs.py` (`normative_statements`),
where the generated pack's `normative-tagged` rule enforces it; this tool imports that
function, so what the author reads here and what the gate asserts cannot differ.

Used by the design-pack skill after every writing round and as the input list
for the assumption hunter. Not shipped into generated repositories.
"""
import argparse
import glob
import importlib.util
import os
import sys

CHECK_DOCS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "templates", "scripts", "check-docs.py")


def load_detector():
    spec = importlib.util.spec_from_file_location("checkdocs", CHECK_DOCS)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.normative_statements


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--specs", default="specs")
    ap.add_argument("--untagged", action="store_true", help="only statements without a provenance tag")
    ap.add_argument("--format", choices=["tsv", "md"], default="tsv")
    ap.add_argument("--untagged-as", default=None, metavar="TAG",
                    help="report untagged statements as this provenance (use `input` for an adopted pack "
                         "that docs/inputs/README.md declares authoritative)")
    args = ap.parse_args()

    normative_statements = load_detector()
    rows = []
    for path in sorted(glob.glob(os.path.join(args.specs, "[0-9][0-9]-*.md"))):
        name = os.path.basename(path)
        is_register = name.endswith("-decision-register.md")
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        for ln, section, tag, statement in normative_statements(text, is_register):
            if tag is None:
                tag = args.untagged_as or "(none)"
            if args.untagged and tag != "(none)":
                continue
            rows.append((name[:2], section, str(ln), tag, statement[:160]))

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
