# Stage D — Self-review, then freeze

Entry: `stage-detect` said `D`. `make check-docs` passes.

Stage D has three owner stops: after the hunter's findings (if any), at the owner's read,
and at the freeze. The skill never stamps the baseline on its own initiative.

## Round D1 — Assumption hunter

1. Produce the statement list:
   `python3 ${CLAUDE_SKILL_DIR}/scripts/extract-normative.py --specs <target>/specs --format md > <scratch>/normative.md`
   (add `--untagged-as input` for an adopted pack; see `stages/C-operationalize.md` §Adopted packs).
2. Spawn a fresh agent (Agent tool, `general-purpose`, no conversation context) with the
   prompt in `stages/hunter.md` §Hunter, substituting the paths. It writes its findings to
   `<scratch>/hunter-findings.md` as decision cards and nothing else.
3. Spawn a second fresh agent with `stages/hunter.md` §Input auditor. It checks every `[input]`
   tag against `docs/inputs/` and writes the unsupported ones to `<scratch>/input-audit.md`.
4. Merge: drop findings that duplicate an existing card (same question, same surface); for the
   rest assign the next Q-IDs, set `blocks` (`specification` when the statement is in the register
   or the spec map, else the earliest package) and append one `card-opened` event each, then
   rebuild. The section a card lands in follows from `blocks`; the index is generated. An unsupported
   `[input]` becomes a card as well, its statement retagged `[inferred]` until answered.
   Note: while a Blocking card lacks an Answer, `stage-detect` reports `A-cards`; that is
   correct, the owner must answer before anything else, and it returns to `D` afterwards.
5. If there are new cards: present them in batches (Stage A form), stop, record the answers as
   `card-answered` events and rebuild, then update the spec statements and their tags, the
   register if a Resolved answer belongs there, and the affected living documents (Stage B
   mechanics). An answer that replaces an earlier one is a new card plus a `card-superseded`
   event on the old one, never an edited answer: the citation moves to the successor, and
   `check-docs` expects exactly that. Then repeat D1 from step 1 with new agents.
   Stop repeating when both agents return zero findings.
6. Report: hunter rounds run, findings per round, cards created and their answers.

## Round D2 — Mechanical

1. `make check-docs` exit 0, which includes `chain-intact` and `projection-fresh`; `make
   verify-chain` exit 0 on its own.
2. `check-docs` covers the tags: `normative-tagged` fails on any untagged statement (an
   adopted pack is exempt by its `docs/inputs/README.md` declaration), and `inferred-zero`
   will fail the moment the baseline is stamped if any `[inferred]` remains, so clear them
   here, before D4. `extract-normative` is the listing to read while doing so. Statements that
   cite an Open card are allowed to stay; the summary line names them, so the owner sees what
   they are deferring past the freeze.
3. `TRACEABILITY.md` contains no `done` or `in progress`; `GAPS.md` has G-001; `PLAN.md` Now is
   FND-01. These are the truthful-empty invariants; `check-docs` covers the rest.

## Round D3 — Owner read

1. Present a reading guide: the order to read the pack in, what each file decides, the Open cards
   and what they block, the `D-NNN` defaults that most affect the implementation (top five), and
   the counts: statements by provenance, cards per surface, files and sizes.
2. Stop. The owner reads and returns corrections.
3. Corrections change spec text (Stage B writing rules, tags kept current), the register, the
   living documents, and `AGENTS.md` where a red line or citation moved. Section numbers do not
   change. After corrections, rerun D1 and D2. Present the delta and stop again.

## Round D4 — Freeze (on the owner's explicit word only)

1. Stamp `specs/README.md`: `Version: 1.0`, `Status: Implementation baseline`, add the date on
   the Status line. This is the last ordinary write to `specs/`, so it happens before step 2.
2. Promote the tiers. The manifest is hard-locked, so this is a ceremony, and the ceremony is
   the record of the freeze:
   `make unlock PATH=.doc-locks REASON="freeze <version>: promote specs/** to hard-locked"`,
   then append to `.doc-locks` (never edit a line; the last matching rule wins, and the guard
   refuses any change that lowers a tier):

   ```
   # Frozen at the baseline, <date>: the contract itself.
   hard-locked: specs/**
   ```

   The unlock is good for the one commit that carries the promotion and the stamped
   `specs/README.md`. `QUESTIONS.md` is not promoted: it is a projection, and `projection-fresh`
   already refuses any change to it that the log does not carry.

   Then `find <target>/specs -type f -exec chmod 0444 {} +`. From here a spec amendment under
   D-002 is a `make unlock PATH=specs/NN-name.md REASON="..."` with its `spec-amendment` event
   appended and the projection rebuilt,
   which is the amendment regime made mechanical rather than remembered. Say in the report that
   the ceremony is now the only way into `specs/`.
3. `make check-docs` exit 0. `make check-locks` exit 0. `stage-detect` says `frozen`.
4. Final report: the counts of D3; the Open cards with their `Blocks:`; the first command the
   implementation agent runs (`SESSION_BOOTSTRAP_PROMPT_SAMPLE.md` prompt 1) and the first
   package (FND-01). State plainly that from here changes to specs go through the amendment
   regime in `AGENTS.md`, not through this skill, and that the owner-intervention count per
   work package is the metric that tells whether Stage A under-elicited a surface; if it
   rises, `reference/elicitation-checklist.md` in this skill is what gets amended.
5. Stop.
