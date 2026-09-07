#!/usr/bin/env python3
"""
check-docs: mechanical truth for the documentation layer.

Fails (exit 1) when the living documents, the entry point or the specification
pack contradict each other in a way that can be detected without judgement.
Every rule here was once a sentence in AGENTS.md; a rule that can be checked
is checked and removed from the prose.

Run from the repository root:  python3 scripts/check-docs.py [--root DIR] [--quiet]

Rules
  citations     every `NN` §M / `specs/NN-name.md` §M / `README.md` §Name cited
                anywhere in the root documents or the specs resolves to a heading
  now-items     no `Now` item in PLAN.md is `done` in TRACEABILITY.md, and every
                `Now` item has a TRACEABILITY.md row
  plan-size     PLAN.md stays under its line ceiling
  gaps          every package or phase a GAPS.md row cites exists in the plan;
                gap IDs are unique and increasing
  packages      every work package in the implementation plan has exactly one
                TRACEABILITY.md row, and no row lacks a package
  traceability  status values are from the allowed set; `done` and
                `in progress` rows carry evidence
  decisions     D-IDs are monotonic and contiguous, every entry has the required
                fields, ADRs carry an owner-approval status, the index matches
                the entries
  register      every bullet in the locked register carries only `[input]` or
                `[Q-NNN]` provenance, and each cited card is Resolved
  provenance    every `[Q-NNN]` tag resolves to a card and every `[D-NNN]` tag
                resolves to a decision; every Resolved card is cited somewhere,
                unless it was superseded, in which case its successor carries the
                citation and has to exist
  cards         every open card has Surface, Source, Question, Options,
                Recommendation and Blocks; Surface is one of the five values
  chain-intact  the event log's hash chain verifies: every hash recomputes,
                every `prev` links, `seq` is contiguous from 1
  projection-fresh
                DECISIONS.md and QUESTIONS.md are byte-for-byte the rebuild of
                their streams, so no hand edit can survive this gate
  red-lines     every bullet under AGENTS.md "Non-negotiable constraints" cites
                at least one spec section
  commands      every `make <target>` listed in AGENTS.md "Commands" is a target
                in the root Makefile
  agents-size   AGENTS.md stays under its byte ceiling
  markers       no unrendered `{{...}}` placeholder or `TBD` remains in the
                documents or in the root Makefile

The report at the end (cards per surface, `[inferred]` statements per file,
open gaps) is informational; only FAIL lines set the exit code.
"""

import argparse
import glob
import json
import os
import re
import sys

# --- configuration -----------------------------------------------------------

ROOT_DOCS = ["AGENTS.md", "PLAN.md", "DECISIONS.md", "GAPS.md", "QUESTIONS.md",
             "TRACEABILITY.md", "CLAUDE.md", "README.md"]
SPECS_DIR = "specs"
PLAN_MAX_LINES = 100
AGENTS_MAX_BYTES = 20_000
SURFACES = {"data", "security", "scope", "external", "ux"}
STATUSES = {"not started", "in progress", "done"}
DECISION_TYPES = {"implementation", "spec-amendment", "adr"}
CARD_FIELDS = ["Surface", "Source", "Question", "Options", "Recommendation", "Blocks"]
DECISION_FIELDS = ["Type", "Decision", "Why", "Alternatives", "Affected specs"]

WP_RE = re.compile(r"\b([A-Z]{2,5}-\d{2,3})\b")
WP_RANGE_RE = re.compile(r"\b([A-Z]{2,5})-(\d{2,3})\.\.(\d{2,3})\b")
PHASE_RE = re.compile(r"\bPhase (\d+)")
Q_TAG_RE = re.compile(r"\[(?:[^\]]*?,\s*)?(Q-\d{3})[^\]]*\]")
D_TAG_RE = re.compile(r"\[(D-\d{3})\]")
INFERRED_RE = re.compile(r"(?<!`)\[inferred\](?!`)")  # a quoted `[inferred]` in prose is not a tag
FILE_TOKEN_RE = re.compile(r"`(?:specs/)?(\d{2})(?:-[a-z0-9-]+\.md)?`|`(?:specs/)?(README\.md)`")
SEC_NUM_RE = re.compile(r"§(\d+(?:\.\d+)?)(?:[–-](\d+))?")

failures = []
notes = []


def fail(rule, where, msg):
    failures.append("FAIL %-12s %s: %s" % (rule, where, msg))


def ok(rule, msg):
    notes.append("ok   %-12s %s" % (rule, msg))


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def exists(path):
    return os.path.isfile(path)


def strip_fences(text):
    """Blank out fenced code blocks, keeping line numbers stable."""
    out, fenced = [], False
    for line in text.splitlines():
        if line.strip().startswith("```"):
            fenced = not fenced
            out.append("")
            continue
        out.append("" if fenced else line)
    return "\n".join(out)


# --- spec index --------------------------------------------------------------

def spec_files(root):
    return sorted(glob.glob(os.path.join(root, SPECS_DIR, "[0-9][0-9]-*.md")))


def spec_by_role(root, role):
    """Locate the spec file whose name ends with the role, e.g. 'decision-register'."""
    for p in spec_files(root):
        if os.path.basename(p)[3:] == role + ".md":
            return p
    return None


def section_index(root):
    """{NN: {numbers}} for numbered headings and {file: {names}} for named ones."""
    numbered, named = {}, {}
    for p in spec_files(root):
        nn = os.path.basename(p)[:2]
        nums = set()
        for m in re.finditer(r"^#{2,4}\s+(\d+(?:\.\d+)*)\.?\s", read(p), re.M):
            nums.add(m.group(1))
        numbered[nn] = nums
    readme = os.path.join(root, SPECS_DIR, "README.md")
    if exists(readme):
        named["specs/README.md"] = {m.group(1).strip().lower()
                                    for m in re.finditer(r"^##+\s+(.+?)\s*$", read(readme), re.M)}
    root_readme = os.path.join(root, "README.md")
    if exists(root_readme):
        named["README.md"] = {m.group(1).strip().lower()
                              for m in re.finditer(r"^##+\s+(.+?)\s*$", read(root_readme), re.M)}
    return numbered, named


def expand_sections(text):
    """From the text following a file token, collect the § references that belong to it."""
    out = []
    # Consume tokens while they look like part of a citation list.
    pos = 0
    tokens = re.finditer(r"\S+", text)
    for t in tokens:
        tok = t.group(0)
        clean = tok.rstrip(",;:).")
        if tok.startswith("§") or tok.startswith("(§"):
            for m in SEC_NUM_RE.finditer(clean):
                a, b = m.group(1), m.group(2)
                if b and "." not in a:
                    lo, hi = int(a), int(b)
                    out.extend(str(i) for i in range(lo, hi + 1))
                else:
                    out.append(a)
            if tok.endswith((")", ".", ";")) and not tok.endswith("§"):
                break
            continue
        if clean in ("and", "&"):
            continue
        break
    return out


def check_citations(root, docs, numbered, named):
    count = 0
    for doc in docs:
        text = read(doc)
        rel = os.path.relpath(doc, root)
        in_fence = False
        for ln, line in enumerate(text.splitlines(), 1):
            if line.strip().startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            for fm in re.finditer(r"`specs/(\d{2}-[a-z0-9-]+\.md)`", line):
                if not exists(os.path.join(root, SPECS_DIR, fm.group(1))):
                    fail("citations", "%s:%d" % (rel, ln), "`specs/%s` is not a file" % fm.group(1))
            for m in FILE_TOKEN_RE.finditer(line):
                nn, readme = m.group(1), m.group(2)
                rest = line[m.end():]
                if readme:
                    nm = re.match(r"\s*§\s*([A-Z][A-Za-z -]*?)(?=\s+rule\b|\s+and\b|[,;:.)`]|$)", rest)
                    if not nm:
                        continue
                    name = nm.group(1).strip().lower()
                    count += 1
                    key = "specs/README.md" if ("specs/" in m.group(0) or name in named.get("specs/README.md", set())) else "README.md"
                    if name not in named.get(key, set()):
                        fail("citations", "%s:%d" % (rel, ln), "`%s` §%s does not resolve" % (key, nm.group(1).strip()))
                    continue
                secs = expand_sections(rest)
                if not secs:
                    continue
                if nn not in numbered:
                    fail("citations", "%s:%d" % (rel, ln), "no spec file numbered %s" % nn)
                    continue
                for s in secs:
                    count += 1
                    if s not in numbered[nn]:
                        fail("citations", "%s:%d" % (rel, ln), "`%s` §%s does not resolve" % (nn, s))
    ok("citations", "%d section citations checked" % count)


# --- plan / traceability -----------------------------------------------------

def plan_packages(root):
    plan = spec_by_role(root, "implementation-plan")
    if not plan:
        fail("packages", SPECS_DIR, "no *-implementation-plan.md found")
        return set(), set(), None
    text = read(plan)
    pkgs = set()
    for m in re.finditer(r"`([A-Z]{2,5}-\d{2,3})`", text):
        pkgs.add(m.group(1))
    phases = set(m.group(1) for m in re.finditer(r"^##\s+\d+\.\s+Phase (\d+)", text, re.M))
    return pkgs, phases, plan


def traceability_rows(root):
    path = os.path.join(root, "TRACEABILITY.md")
    rows = {}
    if not exists(path):
        fail("packages", "TRACEABILITY.md", "file missing")
        return rows
    for ln, line in enumerate(read(path).splitlines(), 1):
        m = re.match(r"^\|\s*([A-Z]{2,5}-\d{2,3})\s*\|(.*)\|\s*$", line)
        if not m:
            continue
        cells = [c.strip() for c in m.group(2).split("|")]
        # Package | Phase | Outcome | Key specs | Status | Evidence
        status = cells[3].lower() if len(cells) >= 5 else ""
        evidence = cells[4] if len(cells) >= 5 else ""
        if m.group(1) in rows:
            fail("packages", "TRACEABILITY.md:%d" % ln, "%s has more than one row" % m.group(1))
        rows[m.group(1)] = (ln, status, evidence)
    return rows


def check_packages_and_traceability(root):
    pkgs, phases, plan = plan_packages(root)
    rows = traceability_rows(root)
    for p in sorted(pkgs - set(rows)):
        fail("packages", "TRACEABILITY.md", "work package %s from the plan has no row" % p)
    for p in sorted(set(rows) - pkgs):
        fail("packages", "TRACEABILITY.md:%d" % rows[p][0], "row %s is not a work package in the plan" % p)
    for p, (ln, status, evidence) in rows.items():
        if status not in STATUSES:
            fail("traceability", "TRACEABILITY.md:%d" % ln, "%s status %r is not one of %s" % (p, status, sorted(STATUSES)))
        elif status in ("done", "in progress") and evidence in ("", "—", "-", "–"):
            fail("traceability", "TRACEABILITY.md:%d" % ln, "%s is %s without evidence" % (p, status))
    if pkgs:
        ok("packages", "%d work packages, %d rows" % (len(pkgs), len(rows)))
    return pkgs, phases, rows


def check_plan(root, rows):
    path = os.path.join(root, "PLAN.md")
    if not exists(path):
        fail("now-items", "PLAN.md", "file missing")
        return
    text = read(path)
    n = len(text.splitlines())
    if n > PLAN_MAX_LINES:
        fail("plan-size", "PLAN.md", "%d lines, ceiling is %d" % (n, PLAN_MAX_LINES))
    else:
        ok("plan-size", "PLAN.md is %d lines" % n)
    heads = [m.group(1) for m in re.finditer(r"^##\s+(\w+)", text, re.M)]
    if heads != ["Now", "Next"]:
        fail("now-items", "PLAN.md", "sections must be exactly `## Now` then `## Next`, found %s" % heads)
    now = text.split("## Now", 1)[1].split("## Next", 1)[0] if "## Now" in text else ""
    items = re.findall(r"^###\s+([A-Z]{2,5}-\d{2,3})\b", now, re.M)
    if not items:
        fail("now-items", "PLAN.md", "no `### <PACKAGE-ID>` item under Now")
    if len(items) > 3:
        fail("now-items", "PLAN.md", "%d Now items; keep 1-3" % len(items))
    for it in items:
        if it not in rows:
            fail("now-items", "PLAN.md", "Now item %s has no TRACEABILITY.md row" % it)
        elif rows[it][1] == "done":
            fail("now-items", "PLAN.md", "Now item %s is already `done` in TRACEABILITY.md" % it)
    if items:
        ok("now-items", "Now = %s" % ", ".join(items))


def check_gaps(root, pkgs, phases):
    path = os.path.join(root, "GAPS.md")
    if not exists(path):
        fail("gaps", "GAPS.md", "file missing")
        return 0
    last = 0
    count = 0
    for ln, line in enumerate(read(path).splitlines(), 1):
        m = re.match(r"^\|\s*G-(\d{3})\s*\|(.*)\|\s*$", line)
        if not m:
            continue
        count += 1
        gid = int(m.group(1))
        if gid <= last:
            fail("gaps", "GAPS.md:%d" % ln, "G-%03d is not greater than the previous gap ID" % gid)
        last = gid
        cells = [c.strip() for c in m.group(2).split("|")]
        plan_item = cells[-1] if cells else ""
        expanded = set()
        for pre, a, b in WP_RANGE_RE.findall(plan_item):
            for i in range(int(a), int(b) + 1):
                expanded.add("%s-%02d" % (pre, i))
        for wp in WP_RE.findall(WP_RANGE_RE.sub(" ", plan_item)):
            expanded.add(wp)
        for wp in sorted(expanded):
            if wp not in pkgs:
                fail("gaps", "GAPS.md:%d" % ln, "G-%03d cites %s, which is not a work package in the plan" % (gid, wp))
        for ph in PHASE_RE.findall(plan_item):
            if ph not in phases:
                fail("gaps", "GAPS.md:%d" % ln, "G-%03d cites Phase %s, which is not in the plan" % (gid, ph))
        if not expanded and not PHASE_RE.search(plan_item):
            fail("gaps", "GAPS.md:%d" % ln, "G-%03d names no work package or phase in its plan-item column" % gid)
    ok("gaps", "%d open gaps" % count)
    return count


# --- decisions ---------------------------------------------------------------

def check_decisions(root):
    path = os.path.join(root, "DECISIONS.md")
    ids = set()
    if not exists(path):
        fail("decisions", "DECISIONS.md", "file missing")
        return ids
    text = strip_fences(read(path))
    heads = list(re.finditer(r"^##\s+D-(\d{3})\s+\((\d{4}-\d{2}-\d{2})\)\s+—\s+(.+?)\s*$", text, re.M))
    bad_heads = [ln for ln, l in enumerate(text.splitlines(), 1)
                 if l.startswith("## D-") and not re.match(r"^##\s+D-\d{3}\s+\(\d{4}-\d{2}-\d{2}\)\s+—\s+.+", l)]
    for ln in bad_heads:
        fail("decisions", "DECISIONS.md:%d" % ln, "entry heading must be `## D-NNN (YYYY-MM-DD) — Title`")
    expected = 1
    for i, h in enumerate(heads):
        n = int(h.group(1))
        ln = text.count("\n", 0, h.start()) + 1
        if n != expected:
            fail("decisions", "DECISIONS.md:%d" % ln, "D-%03d breaks the sequence (expected D-%03d)" % (n, expected))
        expected = n + 1
        ids.add("D-%03d" % n)
        body = text[h.end(): heads[i + 1].start() if i + 1 < len(heads) else len(text)]
        superseded = re.search(r"^Status:\s*superseded by D-\d{3}", body, re.M)
        if superseded:
            continue  # collapsed entry: heading plus status line only
        for f in DECISION_FIELDS:
            if not re.search(r"^%s:\s*\S" % re.escape(f), body, re.M):
                fail("decisions", "DECISIONS.md:%d" % ln, "D-%03d lacks `%s:`" % (n, f))
        tm = re.search(r"^Type:\s*(\S+)", body, re.M)
        if tm and tm.group(1) not in DECISION_TYPES:
            fail("decisions", "DECISIONS.md:%d" % ln, "D-%03d type %r not in %s" % (n, tm.group(1), sorted(DECISION_TYPES)))
        if tm and tm.group(1) == "adr" and not re.search(r"^Owner approval:\s*(pending|granted \d{4}-\d{2}-\d{2}|rejected)", body, re.M):
            fail("decisions", "DECISIONS.md:%d" % ln, "D-%03d is an ADR without `Owner approval: pending | granted YYYY-MM-DD | rejected`" % n)
    # index
    idx = re.search(r"^##\s+Index\s*$(.*?)(?=^##\s+D-\d{3}|\Z)", text, re.M | re.S)
    if not idx:
        fail("decisions", "DECISIONS.md", "no `## Index` section before the first entry")
    else:
        indexed = set(re.findall(r"^\s*-\s+(D-\d{3})\s+—", idx.group(1), re.M))
        for d in sorted(ids - indexed):
            fail("decisions", "DECISIONS.md", "%s has an entry but no index line" % d)
        for d in sorted(indexed - ids):
            fail("decisions", "DECISIONS.md", "%s is indexed but has no entry" % d)
    ok("decisions", "%d entries" % len(ids))
    return ids


# --- questions / cards -------------------------------------------------------

def parse_cards(root):
    """Return {Q-ID: (section, line, body)}, the resolved IDs, and {old: superseding}."""
    path = os.path.join(root, "QUESTIONS.md")
    cards, resolved, superseded = {}, set(), {}
    if not exists(path):
        fail("cards", "QUESTIONS.md", "file missing")
        return cards, resolved, superseded
    text = strip_fences(read(path))
    section = None
    lines = text.splitlines()
    cur = None
    for ln, line in enumerate(lines, 1):
        hm = re.match(r"^##\s+(Blocking|Open|Resolved|Index)\s*$", line)
        if hm:
            section = hm.group(1)
            cur = None
            continue
        cm = re.match(r"^###\s+(Q-\d{3})\b", line)
        if cm and section in ("Blocking", "Open", "Resolved"):
            cur = cm.group(1)
            if cur in cards:
                fail("cards", "QUESTIONS.md:%d" % ln, "%s appears twice" % cur)
            cards[cur] = [section, ln, []]
            if section == "Resolved":
                resolved.add(cur)
            continue
        if section == "Resolved":
            for q in re.findall(r"^\s*-\s+(Q-\d{3})\b", line):
                resolved.add(q)
                cards.setdefault(q, ["Resolved", ln, []])
        if cur:
            cards[cur][2].append(line)
            sm = re.match(r"^\s*-\s*\*?\*?Superseded by\*?\*?:\s*(Q-\d{3})\b", line)
            if sm:
                superseded[cur] = sm.group(1)
    return ({k: (v[0], v[1], "\n".join(v[2])) for k, v in cards.items()},
            resolved, superseded)


def check_cards(cards):
    per_surface = {s: [0, 0] for s in SURFACES}  # open, resolved
    for q, (section, ln, body) in sorted(cards.items()):
        sm = re.search(r"^-?\s*\*?\*?Surface:?\*?\*?:?\s*([a-z]+)", body, re.M)
        surface = sm.group(1) if sm else None
        if section in ("Blocking", "Open"):
            for f in CARD_FIELDS:
                if not re.search(r"^-?\s*\*?\*?%s\*?\*?:" % f, body, re.M):
                    fail("cards", "QUESTIONS.md:%d" % ln, "%s lacks `%s:`" % (q, f))
            if surface not in SURFACES:
                fail("cards", "QUESTIONS.md:%d" % ln, "%s Surface %r is not one of %s" % (q, surface, sorted(SURFACES)))
            if re.search(r"^-?\s*\*?\*?Options\*?\*?:", body, re.M) and not re.search(r"→|->", body):
                fail("cards", "QUESTIONS.md:%d" % ln, "%s options carry no `→ effect on <surface>` consequence" % q)
        if surface in SURFACES:
            per_surface[surface][1 if section == "Resolved" else 0] += 1
    numbers = sorted(int(q[2:]) for q in cards)
    if numbers != list(range(1, len(numbers) + 1)):
        missing = sorted(set(range(1, (numbers[-1] if numbers else 0) + 1)) - set(numbers))
        fail("cards", "QUESTIONS.md", "card IDs are not contiguous from Q-001; missing %s"
             % ", ".join("Q-%03d" % n for n in missing))
    ok("cards", "%d cards" % len(cards))
    return per_surface


# --- register / provenance ---------------------------------------------------

def check_register(root, resolved):
    reg = spec_by_role(root, "decision-register")
    if not reg:
        fail("register", SPECS_DIR, "no *-decision-register.md found")
        return
    text = strip_fences(read(reg))
    rel = os.path.relpath(reg, root)
    # everything before the change-control section is locked content
    cc = re.search(r"^##\s+\d+\.\s+Change control", text, re.M)
    locked = text[:cc.start()] if cc else text
    if not cc:
        fail("register", rel, "no `## N. Change control` section")
    bullets = 0
    for ln, line in enumerate(locked.splitlines(), 1):
        if not re.match(r"^\s*[-*]\s+\S", line):
            continue
        bullets += 1
        tags = re.findall(r"\[([^\]]+)\]\s*$", line.rstrip())
        if not tags:
            fail("register", "%s:%d" % (rel, ln), "bullet has no trailing provenance tag")
            continue
        parts = [p.strip() for p in tags[-1].split(",")]
        for p in parts:
            if p == "input" or p == "recommendation accepted":
                continue
            qm = re.match(r"^(Q-\d{3})$", p)
            if qm:
                if qm.group(1) not in resolved:
                    fail("register", "%s:%d" % (rel, ln), "%s is cited but not Resolved in QUESTIONS.md" % qm.group(1))
                continue
            fail("register", "%s:%d" % (rel, ln), "provenance %r is not allowed in the locked register (only [input] and [Q-NNN])" % p)
    ok("register", "%d locked bullets" % bullets)


def check_provenance(root, docs, cards, resolved, dids, superseded=None):
    cited = set()
    inferred = {}
    for doc in docs:
        rel = os.path.relpath(doc, root)
        text = read(doc)
        for ln, line in enumerate(text.splitlines(), 1):
            for q in Q_TAG_RE.findall(line):
                cited.add(q)
                if q not in cards:
                    fail("provenance", "%s:%d" % (rel, ln), "%s is tagged but has no card in QUESTIONS.md" % q)
            for d in D_TAG_RE.findall(line):
                if d not in dids:
                    fail("provenance", "%s:%d" % (rel, ln), "%s is tagged but has no entry in DECISIONS.md" % d)
            if INFERRED_RE.search(line) and rel.startswith(SPECS_DIR):
                inferred[rel] = inferred.get(rel, 0) + 1
    decisions_text = read(os.path.join(root, "DECISIONS.md")) if exists(os.path.join(root, "DECISIONS.md")) else ""
    superseded = superseded or {}
    for q in sorted(resolved):
        if q in superseded:
            # The owner changed their mind: the statement now cites the superseding
            # card, and the old one stays Resolved and readable for its options. It
            # is the successor that has to be cited, and it is checked on its own row.
            heir = superseded[q]
            if heir not in cards:
                fail("provenance", "QUESTIONS.md",
                     "%s is superseded by %s, which has no card" % (q, heir))
            continue
        if q not in cited and not re.search(r"\b%s\b" % q, decisions_text):
            fail("provenance", "QUESTIONS.md", "%s is Resolved but no spec statement or decision cites it" % q)
    ok("provenance", "%d distinct cards cited" % len(cited))
    return inferred


# --- AGENTS.md ---------------------------------------------------------------

def section_text(text, heading_prefix):
    m = re.search(r"^##\s+%s.*?$(.*?)(?=^##\s|\Z)" % re.escape(heading_prefix), text, re.M | re.S)
    return m.group(1) if m else None


def check_agents(root):
    path = os.path.join(root, "AGENTS.md")
    if not exists(path):
        fail("red-lines", "AGENTS.md", "file missing")
        return
    text = read(path)
    size = os.path.getsize(path)
    if size > AGENTS_MAX_BYTES:
        fail("agents-size", "AGENTS.md", "%d bytes, ceiling is %d; move content into the playbook or docs/" % (size, AGENTS_MAX_BYTES))
    else:
        ok("agents-size", "AGENTS.md is %d bytes" % size)
    red = section_text(strip_fences(text), "Non-negotiable constraints")
    if red is None:
        fail("red-lines", "AGENTS.md", "no `## Non-negotiable constraints` section")
    else:
        n = 0
        for ln, line in enumerate(red.splitlines()):
            if re.match(r"^\s*[-*]\s+\S", line):
                n += 1
                if "§" not in line:
                    fail("red-lines", "AGENTS.md", "red line %d cites no spec section: %s" % (n, line.strip()[:70]))
        ok("red-lines", "%d red lines" % n)
    cmds = section_text(text, "Commands")
    makefile = os.path.join(root, "Makefile")
    if cmds is None:
        fail("commands", "AGENTS.md", "no `## Commands` section")
    elif not exists(makefile):
        fail("commands", "Makefile", "file missing")
    else:
        targets = set(re.findall(r"^([a-zA-Z][a-zA-Z0-9_-]*):", read(makefile), re.M))
        listed = set()
        for fence in re.findall(r"```(?:bash|sh|make)?\n(.*?)```", cmds, re.S):
            listed.update(re.findall(r"^\s*make\s+([a-zA-Z][a-zA-Z0-9_-]*)", fence, re.M))
        for t in sorted(listed - targets):
            fail("commands", "AGENTS.md", "`make %s` is listed but is not a Makefile target" % t)
        ok("commands", "%d listed targets exist" % len(listed & targets))


# --- event log ---------------------------------------------------------------

def check_log(root):
    """chain-intact and projection-fresh. Both are properties of the log, not of
    a document, which is why they live here rather than in any prose rule."""
    log = os.path.join(root, ".log", "events.jsonl")
    if not exists(log):
        ok("chain-intact", "no event log in this repository; chain and projection not checked")
        return (0, True)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    try:
        import eventlog
    except ImportError:
        fail("chain-intact", ".log/events.jsonl", "scripts/eventlog.py is missing; the chain cannot be verified")
        return (0, False)

    lines = eventlog.read_lines(root)
    broken = eventlog.verify(lines)
    if broken:
        fail("chain-intact", ".log/events.jsonl:%d" % broken[0], broken[1])
        return (len(lines), False)   # nothing built from a broken chain is trustworthy
    ok("chain-intact", "%d record(s), every hash and link verified" % len(lines))

    records = [json.loads(line) for line in lines]
    projections = (("DECISIONS.md", eventlog.render_decisions, "rebuild-decisions", "decided"),
                   ("QUESTIONS.md", eventlog.render_questions, "rebuild-questions", "asked or answered"))
    for target, render, command, verb in projections:
        path = os.path.join(root, target)
        if not exists(path):
            continue                 # its own rule already reported the absence
        try:
            rendered = render(records)
        except eventlog.LogError as exc:
            fail("projection-fresh", target, "the stream cannot be projected: %s" % exc)
            continue
        if read(path) != rendered:
            fail("projection-fresh", target,
                 "differs from a fresh rebuild of the log; run `make %s`. "
                 "This file is a projection: an edit here changes nothing that was %s" % (command, verb))
        else:
            ok("projection-fresh", "%s equals the rebuild, byte for byte" % target)
    return (len(lines), True)


# --- markers -----------------------------------------------------------------

def check_markers(root, docs):
    for doc in docs:
        rel = os.path.relpath(doc, root)
        for ln, line in enumerate(read(doc).splitlines(), 1):
            if re.search(r"\{\{[^}]*\}\}", line):
                fail("markers", "%s:%d" % (rel, ln), "unrendered placeholder")
            if re.search(r"\bTBD\b", line):
                fail("markers", "%s:%d" % (rel, ln), "`TBD` left in a document")


# --- main --------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="Mechanical consistency checks for the documentation layer.")
    ap.add_argument("--root", default=".", help="repository root (default: current directory)")
    ap.add_argument("--quiet", action="store_true", help="print only failures and the summary")
    args = ap.parse_args()
    root = os.path.abspath(args.root)

    docs = [os.path.join(root, d) for d in ROOT_DOCS if exists(os.path.join(root, d))]
    specs = spec_files(root)
    readme = os.path.join(root, SPECS_DIR, "README.md")
    all_docs = docs + specs + ([readme] if exists(readme) else [])

    numbered, named = section_index(root)
    check_citations(root, all_docs, numbered, named)
    pkgs, phases, rows = check_packages_and_traceability(root)
    check_plan(root, rows)
    gaps = check_gaps(root, pkgs, phases)
    dids = check_decisions(root)
    cards, resolved, superseded = parse_cards(root)
    per_surface = check_cards(cards)
    check_register(root, resolved)
    inferred = check_provenance(root, all_docs, cards, resolved, dids, superseded)
    check_agents(root)
    events, chain_ok = check_log(root)
    makefile = os.path.join(root, "Makefile")
    check_markers(root, all_docs + ([makefile] if exists(makefile) else []))

    if not args.quiet:
        for n in notes:
            print(n)
    for f in failures:
        print(f)
    print()
    print("summary: %d failure(s)" % len(failures))
    print("cards per surface (open/resolved): " + ", ".join(
        "%s %d/%d" % (s, per_surface[s][0], per_surface[s][1]) for s in ["data", "security", "scope", "external", "ux"]))
    print("[inferred] statements in specs: %s" % (", ".join("%s %d" % kv for kv in sorted(inferred.items())) or "none"))
    print("open gaps: %d" % gaps)
    print("event log: %d record(s), chain %s" % (events, "intact" if chain_ok else "BROKEN"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
