#!/usr/bin/env python3
"""
log-append: the only sanctioned writer to the event log.

It reads the last record to learn `seq` and `hash`, refuses to continue if that
record does not verify (never append onto a broken chain), builds the new record,
computes `prev` and `hash` over the canonical form, and appends exactly one line.
It also refuses an event that the stream's projection could not fold, because the
log is append-only and such an event could never be taken back. For the same
reason a `decision-added` whose text cites a section that does not exist in a
spec file that does is refused: `check-docs` would fail on it and nothing could
remove it. A citation into a spec not written yet is allowed; the gate checks it
later, and supersession then retires the record's text from the check.
It always appends: there is no deduplication, and recording the same event twice
records it twice.

The canonical form and what the chain does and does not guarantee are documented
at the top of `eventlog.py`.

    python3 scripts/log-append.py --type decision-added \
        --set id=D-005 --set date=2026-09-04 --set title="API base path" \
        --set type=implementation --set decision="..." --set why="..." \
        --set alternatives="..." --set affected_specs="none."

    python3 scripts/log-append.py --type decision-superseded \
        --set id=D-005 --set by=D-011

    echo '{"id":"D-005", ...}' | python3 scripts/log-append.py \
        --type decision-added --payload-file -

    python3 scripts/log-append.py --stream questions --type card-opened --payload-file cards.json
        # cards.json holds a JSON ARRAY: every element is validated and checked against the
        # projection before anything is written, then all are appended in order. One
        # command for a batch, instead of one process per card.

Exit status: 0 appended, 2 usage or invalid event, 3 the chain does not verify.
"""

import argparse
import datetime
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import eventlog  # noqa: E402


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main():
    ap = argparse.ArgumentParser(description="Append one event to the hash-chained log.")
    ap.add_argument("--root", default=".", help="repository root (default: current directory)")
    ap.add_argument("--stream", default=eventlog.DECISIONS_STREAM, help="stream the event belongs to")
    ap.add_argument("--type", required=True, dest="event_type", help="event type within the stream")
    ap.add_argument("--actor", default="agent", choices=list(eventlog.ACTORS), help="who caused it")
    ap.add_argument("--ts", default=None, help="ISO-8601 UTC timestamp (default: now)")
    ap.add_argument("--payload", default=None, help="payload as a JSON object")
    ap.add_argument("--payload-file", default=None, help="file holding the payload JSON, `-` for stdin")
    ap.add_argument("--set", action="append", default=[], metavar="KEY=VALUE",
                    help="one payload field; repeatable, merged over --payload")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    root = os.path.abspath(args.root)

    payload = {}
    sources = [bool(args.payload), bool(args.payload_file)]
    if all(sources):
        sys.stderr.write("log-append: use --payload or --payload-file, not both\n")
        return 2
    raw = args.payload
    if args.payload_file:
        raw = sys.stdin.read() if args.payload_file == "-" else open(args.payload_file, encoding="utf-8").read()
    if raw:
        try:
            payload = json.loads(raw)
        except ValueError as exc:
            sys.stderr.write("log-append: payload is not valid JSON: %s\n" % exc)
            return 2
    batch = isinstance(payload, list)
    payloads = payload if batch else [payload]
    if batch and args.set:
        sys.stderr.write("log-append: --set cannot be combined with a JSON array payload\n")
        return 2
    if not payloads:
        sys.stderr.write("log-append: the payload array is empty\n")
        return 2
    for pair in args.set:
        if "=" not in pair:
            sys.stderr.write("log-append: --set wants KEY=VALUE, got %r\n" % pair)
            return 2
        key, value = pair.split("=", 1)
        payloads[0][key] = value

    validated = []
    for i, one in enumerate(payloads):
        try:
            validated.append(eventlog.admit(root, args.stream, args.event_type, one))
        except eventlog.LogError as exc:
            sys.stderr.write("log-append: %s%s\n" % ("element %d: " % i if batch else "", exc))
            return 2

    path = eventlog.log_path(root)
    directory = os.path.dirname(path)
    if not os.path.isdir(directory):
        os.makedirs(directory)
    if not os.path.exists(path):
        # An empty log is a valid genesis state: seq 1 links to 64 zeros.
        open(path, "w", encoding="utf-8").close()

    try:
        records = eventlog.load(root)
    except eventlog.LogError as exc:
        sys.stderr.write("log-append: refusing to append onto a broken chain.\n  %s\n" % exc)
        return 3

    # Build and check every record before writing any: a batch is all or nothing.
    events = [(args.stream, args.event_type, args.actor, one) for one in validated]
    try:
        new_records = eventlog.chain_onto(records, events, args.ts or now())
    except eventlog.Unprojectable as exc:
        sys.stderr.write("log-append: %sthis event cannot be projected, so it is refused "
                         "rather than appended to a log that nothing can take it out of.\n  %s\n"
                         % ("element %d: " % exc.index if batch else "", exc))
        return 2
    eventlog.write_records(root, new_records)

    if not args.quiet:
        for record in new_records:
            print("appended seq %d %s/%s hash %s"
                  % (record["seq"], record["stream"], record["type"], record["hash"][:16]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
