#!/usr/bin/env python3
"""
log-land: land one package's staged work, after it integrates.

A session working on a package under an orchestrator never appends to the log
and never edits the documents every package shares (see the staging section of
`eventlog.py` for why). It stages instead:

  .log/pending/<PACKAGE>.jsonl       the events it would have appended, IDs as
                                     placeholders (D-NEW-1, Q-NEW-1, ...)
  docs/layers/<PACKAGE>.md           its layer note, whose `## Landing` section
                                     holds its updates to the shared documents

`make land TASK=<PACKAGE>` runs this, one package at a time, in the order the
orchestrator integrates them. It:

  1. validates every staged event with the checks `log-append.py` applies, and
     every landing line, before it writes anything;
  2. assigns the next contiguous real IDs in staged order (D-, Q-, and G- for a
     gap row the package adds) and rewrites the placeholders in the events, the
     landing lines and the layer note;
  3. appends the events through the same functions `log-append.py` uses, so
     there is one writer and one set of refusals;
  4. rebuilds DECISIONS.md and QUESTIONS.md, applies the landing lines to
     TRACEABILITY.md, GAPS.md and PLAN.md, and adds the package's line to the AGENTS.md "Layer notes" index when it lands `done`;
  5. removes the staging file and the `## Landing` section.

On any refusal it exits non-zero having changed nothing: every new file content
is computed in memory first, and the first write happens only once all of it is.

Landing lines, one per bullet under `## Landing`, cells separated by ` | `:

  - traceability: <status> | <evidence>          this package's TRACEABILITY.md row
  - gap-add: G-NEW-n | <gap> | <consequence> | <evidence to close> | <plan item>
  - gap-narrow: G-NNN | <gap> | <consequence> | <evidence to close> | <plan item>
  - gap-retire: G-NNN
  - plan-remove                                  this package's `Now` item in PLAN.md

Exit status: 0 landed, 2 usage or refused, 3 the chain does not verify.
"""

import argparse
import datetime
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import eventlog  # noqa: E402

LAYERS_DIR = os.path.join("docs", "layers")
LAYER_INDEX_HEADING = "Layer notes"
STATUSES = ("not started", "in progress", "done")
EVIDENCE_MAX_CHARS = 1000
GAP_CELL_MAX_CHARS = 2000
EMPTY_INDEX_RE = re.compile(r"^None yet\b.*$", re.M)


class Refused(Exception):
    """Landing would be wrong; nothing has been written."""


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


# --- the layer note's `## Landing` section ------------------------------------

def landing_section(note):
    """(text before, the section's body, text after) or None when there is none."""
    m = re.search(r"^##\s+Landing\s*$", note, re.M)
    if not m:
        return None
    rest = note[m.end():]
    nxt = re.search(r"^##\s", rest, re.M)
    body = rest[:nxt.start()] if nxt else rest
    after = rest[nxt.start():] if nxt else ""
    return note[:m.start()], body, after


def without_landing(note):
    parts = landing_section(note)
    if parts is None:
        return note
    before, _, after = parts
    return (before.rstrip("\n") + "\n" + ("\n" + after if after else "")).rstrip("\n") + "\n"


def landing_lines(body):
    """[(kind, [cells])] from the section body; Refused on a line it cannot read."""
    out = []
    for raw in body.splitlines():
        line = raw.strip()
        if not line or line.startswith("<!--"):
            continue
        m = re.match(r"^[-*]\s+([a-z-]+)\s*(?::\s*(.*))?$", line)
        if not m:
            raise Refused("`## Landing` line %r is not `- <kind>: <cells>`" % line[:60])
        kind, rest = m.group(1), (m.group(2) or "").strip()
        cells = [c.strip() for c in rest.split(" | ")] if rest else []
        out.append((kind, cells))
    return out


# --- applying the landing lines ------------------------------------------------

def apply_traceability(text, package, cells):
    if len(cells) != 2:
        raise Refused("`traceability:` takes `<status> | <evidence>`, got %d cell(s)" % len(cells))
    status, evidence = cells[0].lower(), cells[1]
    if status not in STATUSES:
        raise Refused("traceability status %r is not one of %s" % (status, ", ".join(STATUSES)))
    if status in ("done", "in progress") and evidence in ("", "—", "-"):
        raise Refused("traceability: %s is %s without evidence" % (package, status))
    if len(evidence) > EVIDENCE_MAX_CHARS:
        raise Refused("traceability: %d characters of evidence, ceiling is %d (`evidence-size`)"
                      % (len(evidence), EVIDENCE_MAX_CHARS))
    lines, hit = text.split("\n"), False
    for i, line in enumerate(lines):
        m = re.match(r"^\|\s*%s\s*\|(.*)\|\s*$" % re.escape(package), line)
        if not m:
            continue
        row = [c.strip() for c in m.group(1).split("|")]
        if len(row) < 5:
            raise Refused("TRACEABILITY.md row %s does not have six cells" % package)
        row[3], row[4] = status, evidence
        lines[i] = "| %s | %s |" % (package, " | ".join(row))
        hit = True
    if not hit:
        raise Refused("TRACEABILITY.md has no row for %s" % package)
    return "\n".join(lines), status


def gap_rows(text):
    return [(i, int(m.group(1))) for i, line in enumerate(text.split("\n"))
            for m in [re.match(r"^\|\s*G-(\d{3})\s*\|", line)] if m]


def apply_gap(text, kind, cells):
    lines = text.split("\n")
    rows = dict((n, i) for i, n in gap_rows(text))
    if kind == "gap-retire":
        if len(cells) != 1 or not re.fullmatch(r"G-\d{3}", cells[0]):
            raise Refused("`gap-retire:` takes one `G-NNN`, got %r" % " | ".join(cells))
        n = int(cells[0][2:])
        if n not in rows:
            raise Refused("GAPS.md has no row %s to retire" % cells[0])
        del lines[rows[n]]
        return "\n".join(lines)
    if len(cells) != 5:
        raise Refused("`%s:` takes `G-ID | gap | consequence | evidence to close | plan item`, "
                      "got %d cell(s)" % (kind, len(cells)))
    for cell in cells[1:]:
        if len(cell) > GAP_CELL_MAX_CHARS:
            raise Refused("%s: a cell of %d characters, ceiling is %d (`gaps-size`)"
                          % (cells[0], len(cell), GAP_CELL_MAX_CHARS))
    row = "| %s |" % " | ".join(cells)
    if kind == "gap-narrow":
        if not re.fullmatch(r"G-\d{3}", cells[0]) or int(cells[0][2:]) not in rows:
            raise Refused("GAPS.md has no row %s to narrow" % cells[0])
        lines[rows[int(cells[0][2:])]] = row
        return "\n".join(lines)
    if kind == "gap-add":
        if not re.fullmatch(r"G-\d{3}", cells[0]):
            raise Refused("`gap-add:` starts with a G-NEW-n placeholder, got %r" % cells[0])
        last = max(rows.values()) if rows else None
        if last is None:
            raise Refused("GAPS.md has no gap table to add a row to")
        lines.insert(last + 1, row)
        return "\n".join(lines)
    raise Refused("unknown landing line `%s:`" % kind)


def apply_plan_remove(text, package):
    m = re.search(r"^###\s+%s\b.*?(?=^###\s|^##\s|\Z)" % re.escape(package), text, re.M | re.S)
    if not m or "## Now" not in text[:m.start()] or "## Next" in text[:m.start()]:
        raise Refused("PLAN.md has no `### %s` item under `## Now` to remove" % package)
    return text[:m.start()] + text[m.end():]


def apply_index(text, package, title):
    """Add `- PKG — title → docs/layers/PKG.md` to the AGENTS.md index, once."""
    m = re.search(r"^##\s+%s\s*$" % re.escape(LAYER_INDEX_HEADING), text, re.M)
    if not m:
        raise Refused("AGENTS.md has no `## %s` section to index the note in" % LAYER_INDEX_HEADING)
    start = m.end()
    nxt = re.search(r"^##\s", text[start:], re.M)
    end = start + nxt.start() if nxt else len(text)
    section = text[start:end]
    if re.search(r"^\s*-\s+%s\b" % re.escape(package), section, re.M):
        return text
    line = "- %s — %s → `docs/layers/%s.md`" % (package, title, package)
    if EMPTY_INDEX_RE.search(section):
        section = EMPTY_INDEX_RE.sub(line, section, count=1)
    else:
        items = list(re.finditer(r"^\s*-\s+[A-Z]{2,5}-\d{2,3}\b.*$", section, re.M))
        if items:
            at = items[-1].end()
            section = section[:at] + "\n" + line + section[at:]
        else:
            section = section.rstrip("\n") + "\n\n" + line + "\n\n"
    return text[:start] + section + text[end:]


def note_title(note, package):
    m = re.search(r"^#\s+%s\s*[—-]+\s*(.+?)\s*$" % re.escape(package), note, re.M)
    if not m:
        raise Refused("the layer note's title is not `# %s — <the layer in a few words>`; "
                      "the AGENTS.md index line is derived from it" % package)
    return m.group(1)


# --- ID assignment ----------------------------------------------------------------

def next_gap_number(root, gaps_text):
    """One past the highest gap ID ever used: in the file, and in its Git history.

    A retired gap's row is removed and its ID is never reused, so the file alone
    can under-count; the history is read when there is one.
    """
    seen = [n for _, n in gap_rows(gaps_text)]
    try:
        log = subprocess.run(["git", "-C", root, "log", "-p", "--format=", "--", "GAPS.md"],
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             universal_newlines=True, check=False).stdout
        seen += [int(n) for n in re.findall(r"^[-+ ]\|\s*G-(\d{3})\s*\|", log, re.M)]
    except OSError:
        pass
    return (max(seen) if seen else 0) + 1


def assign(staged_ids, gap_placeholders, records, next_gap):
    """{placeholder: real ID} in staged order, contiguous from the log's next IDs."""
    next_d = len(eventlog.project_decisions(records)) + 1
    next_q = len(eventlog.project_questions(records)) + 1
    mapping = {}
    for placeholder in staged_ids:
        if placeholder.startswith("D-"):
            mapping[placeholder], next_d = "D-%03d" % next_d, next_d + 1
        else:
            mapping[placeholder], next_q = "Q-%03d" % next_q, next_q + 1
    for placeholder in gap_placeholders:
        mapping[placeholder], next_gap = "G-%03d" % next_gap, next_gap + 1
    return mapping


# --- landing -------------------------------------------------------------------------

def land(root, package, ts):
    """Compute everything, then write it. Returns the report lines."""
    events_path = eventlog.pending_path(root, package)
    note_path = os.path.join(root, LAYERS_DIR, "%s.md" % package)
    note = read(note_path) if os.path.isfile(note_path) else None
    landing = landing_section(note) if note is not None else None
    if not os.path.isfile(events_path) and landing is None:
        raise Refused("%s has nothing staged: no %s and no `## Landing` section in %s"
                      % (package, os.path.relpath(events_path, root),
                         os.path.relpath(note_path, root)))

    # Form: the same checks `check-docs` (`pending`) runs, refused here too, so a
    # landing never depends on the gate having been run first.
    staged = eventlog.read_jsonl(events_path) if os.path.isfile(events_path) else []
    problems = eventlog.staged_problems(staged)
    if problems:
        raise Refused("the staged work is not well-formed:\n  %s"
                      % "\n  ".join("line %d: %s" % p for p in problems))

    try:
        records = eventlog.load(root)
    except eventlog.LogError as exc:
        err = Refused("refusing to land onto a broken chain.\n  %s" % exc)
        err.status = 3
        raise err

    # IDs, in staged order.
    staged_ids = [obj["payload"]["id"] for _, obj, _ in staged
                  if (obj["stream"], obj["type"]) in eventlog.ADDS]
    lines = landing_lines(landing[1]) if landing else []
    gap_placeholders = []
    for kind, cells in lines:
        if kind != "gap-add":
            continue
        if not cells or not re.fullmatch(r"G-NEW-[1-9]\d*", cells[0]):
            raise Refused("`gap-add:` starts with a G-NEW-n placeholder, got %r: two packages "
                          "landing from one base would both take a real ID"
                          % (cells[0] if cells else ""))
        if cells[0] in gap_placeholders:
            raise Refused("%s is added twice in `## Landing`" % cells[0])
        gap_placeholders.append(cells[0])
    gaps_path = os.path.join(root, "GAPS.md")
    gaps_text = read(gaps_path) if os.path.isfile(gaps_path) else ""
    mapping = assign(staged_ids, gap_placeholders, records, next_gap_number(root, gaps_text))

    # Events: through the log's own door, then onto the chain, in memory.
    events = []
    for lineno, obj, _ in staged:
        payload = eventlog.substitute(obj["payload"], mapping)
        try:
            payload = eventlog.admit(root, obj["stream"], obj["type"], payload)
        except eventlog.LogError as exc:
            raise Refused("staged line %d: %s" % (lineno, exc))
        events.append((obj["stream"], obj["type"], obj["actor"], payload))
    try:
        new_records = eventlog.chain_onto(records, events, ts)
    except eventlog.Unprojectable as exc:
        raise Refused("staged event %d cannot be projected, so it is refused rather than appended "
                      "to a log that nothing can take it out of.\n  %s" % (exc.index + 1, exc))
    folded = records + new_records

    # Every file this landing writes, as its new text; nothing is written yet.
    writes = {}

    def current(rel):
        if rel in writes:
            return writes[rel]
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            raise Refused("%s is missing" % rel)
        return read(path)

    if new_records:
        writes["DECISIONS.md"] = eventlog.render_decisions(folded)
        writes["QUESTIONS.md"] = eventlog.render_questions(folded)

    status = None
    for kind, cells in lines:
        cells = [eventlog.substitute(c, mapping) for c in cells]
        if kind == "traceability":
            text, status = apply_traceability(current("TRACEABILITY.md"), package, cells)
            writes["TRACEABILITY.md"] = text
        elif kind in ("gap-add", "gap-narrow", "gap-retire"):
            writes["GAPS.md"] = apply_gap(current("GAPS.md"), kind, cells)
        elif kind == "plan-remove":
            if cells and cells != [package]:
                raise Refused("`plan-remove` removes this package's own item, not %s" % cells[0])
            writes["PLAN.md"] = apply_plan_remove(current("PLAN.md"), package)
        else:
            raise Refused("unknown landing line `%s:`; the forms are traceability, gap-add, "
                          "gap-narrow, gap-retire and plan-remove" % kind)

    if note is not None:
        new_note = without_landing(eventlog.substitute(note, mapping))
        if new_note != note:
            writes[os.path.relpath(note_path, root)] = new_note
        if status == "done":
            writes["AGENTS.md"] = apply_index(current("AGENTS.md"), package, note_title(new_note, package))

    # A file the landing cannot write would stop it half way; find out first.
    for rel in sorted(writes) + ([os.path.join(eventlog.LOG_DIR, eventlog.LOG_NAME)] if new_records else []):
        path = os.path.join(root, rel)
        if os.path.exists(path) and not os.access(path, os.W_OK):
            raise Refused("%s is not writable; a hard-locked file is written only after "
                          "`make unlock`" % rel)

    # Everything is known and nothing was refused: write.
    eventlog.write_records(root, new_records)
    for rel, text in writes.items():
        with open(os.path.join(root, rel), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
    removed = []
    if os.path.isfile(events_path):
        os.remove(events_path)
        removed.append(os.path.relpath(events_path, root))

    report = []
    if new_records:
        report.append("appended seq %d..%d" % (new_records[0]["seq"], new_records[-1]["seq"]))
    if mapping:
        report.append(", ".join("%s → %s" % kv for kv in mapping.items()))
    if writes:
        report.append("wrote %s" % ", ".join(sorted(writes)))
    if removed:
        report.append("removed %s" % ", ".join(removed))
    return report


def main():
    ap = argparse.ArgumentParser(description="Land one package's staged events and document "
                                             "updates.")
    ap.add_argument("package", help="the work package ID, e.g. LDG-01")
    ap.add_argument("--root", default=".", help="repository root (default: current directory)")
    ap.add_argument("--ts", default=None, help="ISO-8601 UTC timestamp of the records (default: now)")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()
    root = os.path.abspath(args.root)
    try:
        report = land(root, args.package, args.ts or now())
    except Refused as exc:
        sys.stderr.write("land: %s: refused; nothing was written.\n  %s\n" % (args.package, exc))
        return getattr(exc, "status", 2)
    if not args.quiet:
        for line in report:
            print("land: %s: %s" % (args.package, line))
    return 0


if __name__ == "__main__":
    sys.exit(main())
