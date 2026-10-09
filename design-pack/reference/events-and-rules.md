# Events and rules — the lookup

Not read every session. This file exists so that a stage never has to open
`templates/scripts/eventlog.py` or `check-docs.py` to learn a payload field or a rule
name. Everything below is what those two scripts enforce; they remain the authority,
and `scripts/test-check-docs.sh` fails when this file and the checker disagree about
which rules exist.

## The event log: every event and what its payload needs

One command per append, or a JSON array in one file for a whole round:

```
python3 ${CLAUDE_SKILL_DIR}/templates/scripts/log-append.py --root <target> \
    --stream <decisions|questions> --type <event> --payload-file <file|->
```

`--payload-file -` reads one object from stdin; a file holding a JSON **array** appends
the whole batch, every element validated first, all or nothing. `--set key=value` adds or
overrides one field (`--set recommendation_accepted=true`). The tool refuses an event no
projection could fold, and a `decision-added` whose text cites a spec section that does
not exist — on an append-only log neither could ever be taken back.

### Stream `decisions`

| Event | Required payload | Notes |
| --- | --- | --- |
| `decision-added` | `id` (`D-NNN`), `date` (`YYYY-MM-DD`), `title`, `type`, `decision`, `why`, `alternatives`, `affected_specs` | `type` is `implementation`, `spec-amendment` or `adr`. An `adr` also needs `approval` (`pending`, `granted`, `rejected`), and `granted` needs `approval_date`. |
| `decision-superseded` | `id`, `by` (both `D-NNN`) | Renders `Status: superseded by D-MMM` on the old entry and collapses it. A record may not supersede itself. |
| `adr-approval-changed` | `id`, `approval` | `approval_date` (or `date`) when `granted`; refused on any other state. Only an `adr` has an approval. |

### Stream `questions`

| Event | Required payload | Notes |
| --- | --- | --- |
| `card-opened` | `id` (`Q-NNN`), `title`, `surface`, `source`, `question`, `options`, `blocks` | `surface` is one of the five. `options` is an array of at least two, each carrying `→ effect on <surface>: …` — an option with no consequence is refused. `blocks` is `specification`, always. `recommendation` is optional **here** and mandatory in the method: `check-docs` (`cards`) fails an open card without one. |
| `card-answered` | `id`, `answer`, `date` | `--set recommendation_accepted=true` renders `- Answer: B (2026-09-03; recommendation accepted)`; without it, `- Answer: B (2026-09-03)`. |
| `card-deferred` | `id`, `blocks` | `blocks` names the phase or work package the answer changes, never `specification`. This is what moves a card to `## Open`, and only the owner's word causes it. |
| `card-reactivated` | `id` | `blocks` optional; defaults back to `specification`. |
| `card-resolved` | `id` | Appended when the spec text carrying the card's `[Q-NNN]` tag exists, not when the answer is given. |
| `card-superseded` | `id`, `by` (both `Q-NNN`) | The old card stays Resolved and readable; the citation moves to the successor, which `check-docs` (`provenance`) then expects. |

Every record also carries `seq`, `ts`, `actor`, `stream`, `type`, `prev` and `hash`, all
written by the tool. Nothing else writes the log.

## `check-docs`: the rule names

`--only` takes any comma-separated subset of these, and a scoped run says how many
failures of other rules it dropped, so it never looks like a clean one.

| Rule | Fails when |
| --- | --- |
| `citations` | a `NN` §M or `README.md` §Name citation resolves to no heading |
| `now-items` | `PLAN.md` has no `Now` item, more than three, one already `done`, or one with no traceability row; a `Lane:` differs from the plan's; or, among the items with a `Branch:` (a dispatched wave), two share a lane, one is blocked by an open card, or one depends on a package not `done` |
| `plan-size` | `PLAN.md` is over its line ceiling |
| `packages` | a work package has no traceability row, or a row names no package |
| `traceability` | a status is outside the three values, or a `done`/`in progress` row carries no evidence |
| `evidence-size` | an Evidence cell is over its ceiling: it holds the run that proved the **current** status |
| `gaps` | a gap cites a package or phase the plan does not have, or the IDs are not increasing |
| `gaps-size` | a `GAPS.md` cell is over its ceiling: a row holds one gap, not a history |
| `decisions` | a `D-NNN` breaks the sequence, lacks a field, is an ADR without an approval state, or is missing from the index |
| `register` | the locked register holds anything but `[input]` or a Resolved `[Q-NNN]` |
| `provenance` | a tag resolves to nothing, or a Resolved card is cited by nothing and was not superseded |
| `normative-tagged` | a normative statement in `specs/` carries no provenance tag |
| `inferred-zero` | an `[inferred]` survives the baseline stamp |
| `cards` | an open card lacks one of its six fields, or its surface is not one of the five |
| `chain-intact` | a hash does not recompute, a `prev` does not link, or `seq` is not contiguous |
| `projection-fresh` | `DECISIONS.md` or `QUESTIONS.md` differs from a fresh rebuild |
| `red-lines` | a red line in `AGENTS.md` cites no spec section |
| `commands` | `AGENTS.md` lists a `make` target the `Makefile` does not have |
| `agents-size` | `AGENTS.md` is over its byte ceiling |
| `layer-notes` | a `done` package has no layer note or no index line, a note names no package, or an `AGENTS.md` heading names a package |
| `pending` | a staged event is not well-formed for its stream, a staging file assigns a real `D-`/`Q-` ID, or a `done` package still has staged work |
| `markers` | an unrendered `{{...}}` or a `TBD` survives |
| `task-policy` | a package lacks one of its six characteristics, a derived one disagrees with the pack, a lane is not one the plan lists, a `Depends on:` crosses a phase, forms a cycle or misses a contract package whose section it cites, or the prompt-selection table names something that is not a prompt or a characteristic |

Two readers run instead of the rules and never judge the pack: `--task PACKAGE|all`
prints the characteristics and the live `blocked-by`, and `--brief PACKAGE`
(`make brief TASK=...`) prints everything a session on that package has to read.
