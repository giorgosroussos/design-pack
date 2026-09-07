---
name: design-pack
description: Generate the design documentation pack that an implementation agent works from - a frozen specification contract, an operating layer (AGENTS.md, pointers, loop prompts, command contract) and living state documents - by eliciting the owner's decisions through decision cards, in rounds, never in one shot. Design phase only; writes no code.
argument-hint: "[target-dir]"
disable-model-invocation: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
  - Bash(bash ${CLAUDE_SKILL_DIR}/scripts/*)
  - Bash(python3 ${CLAUDE_SKILL_DIR}/scripts/*)
  - Bash(python3 ${CLAUDE_SKILL_DIR}/templates/scripts/*)
  - Bash(make check-docs)
  - Bash(python3 scripts/check-docs.py*)
---

# design-pack

Turns raw requirements plus owner decisions into a repository-ready documentation pack:
`specs/` (the frozen contract), `AGENTS.md` and its pointer files (the operating layer),
`PLAN.md`, `DECISIONS.md`, `GAPS.md`, `QUESTIONS.md`, `TRACEABILITY.md` (the living
documents), a root `Makefile` whose `check-docs` target enforces their consistency, a
`.doc-locks` manifest that git hooks enforce over the diff, an append-only hash-chained event
log at `.log/events.jsonl` whose projection is `DECISIONS.md`, and `docs/inputs/` holding the
raw material. The implementation agent then works from
`AGENTS.md` alone; the generated repository never references this skill.

The target directory is `$0` if given, else the current working directory. Write every
generated file in English unless the owner asks for another language; converse in the
owner's language.

## Start every invocation here

1. `bash ${CLAUDE_SKILL_DIR}/scripts/stage-detect.sh <target>` prints the stage. There is no
   state file; the documents are the state.
2. Read the matching stage file and follow it: `A-intake`, `A-cards` → `stages/A-elicit.md`;
   `B-fileset`, `B-write` → `stages/B-specify.md`; `C` → `stages/C-operationalize.md`;
   `D` → `stages/D-review.md`; `frozen` → say so, point at the amendment regime in the target's
   `AGENTS.md`, offer only a re-run of the hunter (Stage D round D1) on request, and stop.
3. Read `reference/surfaces.md`, `reference/decision-card.md` and `reference/provenance.md`
   once per session before any stage work. They are short and they are the core.
4. An existing spec set the owner adopts as-is enters at `C` once `docs/inputs/README.md`
   declares it authoritative; `stages/C-operationalize.md` §Adopted packs says what changes.

## The one problem this skill exists to solve

The output's quality is decided by which decisions the owner makes and which the agent
makes. An answer the skill gives itself, however reasonable, becomes a locked constraint
nobody questions again. Four mechanisms, all mandatory, working together:

1. **The five surfaces** (`reference/surfaces.md`): a question is the owner's if and only if
   its plausible answers change data, security, scope, external commitments or product
   identity/UX. Everything else the skill decides and records as `D-NNN` with alternatives.
2. **The decision card** (`reference/decision-card.md`): the only shape a question to the
   owner may take. Surface, source, one-sentence question, options each with its effect on the
   surface, a mandatory recommendation, what it blocks. If "effect on surface" cannot be filled,
   it is not a card. If it can, it must be asked. There is no third category.
3. **Provenance on every normative statement** (`reference/provenance.md`): `[input]`,
   `[Q-NNN]`, `[D-NNN]` or `[inferred]`, trailing, on every MUST/SHOULD/MAY. The locked
   register may hold only `[input]` and Resolved `[Q-NNN]`; `check-docs` enforces it.
4. **The assumption hunter** (`stages/hunter.md`): a fresh agent with one mandate reads the
   pack and writes every surface-touching statement that is not `[input]` or `[Q-NNN]` as a
   card. It fixes nothing and judges nothing.

Deferral is allowed: a card may stay Open with `Blocks:` set, and the loop's third prompt
raises it before that phase. Silent decision is the only unacceptable state.

## Hard rules

- **Rounds, never one shot.** Every stage file defines where it stops for the owner. A stage
  that has not reached its stop does not skip ahead; a stop is a real end of turn. Never write
  the whole pack in one turn, even when asked to "just generate it".
- **Never answer a surface question yourself.** Not to unblock a batch, not because the answer
  is obvious, not because the owner is busy. Write the card, recommend, wait.
- **Never put anything but `[input]` or Resolved `[Q-NNN]` in the locked register.**
- **Living documents start truthful-empty.** `TRACEABILITY.md` has no `done` or `in progress`
  anywhere; `GAPS.md` has G-001; `PLAN.md` Now is FND-01, the command contract. Nothing
  "exists" until a command ran and passed, and the skill runs no such command.
- **A rule that can be a `check-docs` assertion is one**, and is not written as prose in
  `AGENTS.md`. When you find yourself writing "always" or "never" into `AGENTS.md`, ask
  whether `templates/scripts/check-docs.py` could check it.
- **A lock that can be enforced is enforced.** "Append-only" and "locked" are not asks the
  agent must remember; `check-docs` cannot see them either, because both are properties of a
  diff and not of a snapshot. `.doc-locks` declares the tier of every path, and
  `templates/scripts/lock-guard.py` reads the diff from `.githooks/pre-commit` locally and from
  the pre-receive mirror on the remote, which is the bypass-proof half. A hard-locked file
  changes only through `make unlock PATH=... REASON="..."`, recorded in `UNLOCKS.md` and good
  for exactly one commit. Tiers are promoted, never assumed: a file is locked when the stage
  that legitimately writes it is over, which is why `specs/` and `QUESTIONS.md` are free until
  the freeze promotes them (`stages/D-review.md` D4).
- **One home per rule.** `AGENTS.md`, `CLAUDE.md`, the playbook and the prompts point at each
  other; they do not repeat each other.
- **Decisions and cards are logs, not files.** `DECISIONS.md` and `QUESTIONS.md` are projections
  of the `decisions` and `questions` streams of `.log/events.jsonl`, rendered by
  `templates/scripts/rebuild-decisions.py` and `rebuild-questions.py`. The log is the source of
  truth: in every stage, record a decision or a card by appending an event and rebuilding, never
  by writing into the file. A card moves between Blocking, Open and Resolved because
  `card-deferred`, `card-reactivated` or `card-resolved` says so, so the movement is history
  instead of a diff nobody can audit. `check-docs` verifies the chain (`chain-intact`) and that
  both files equal a fresh rebuild (`projection-fresh`), so a hand edit fails the gate instead of
  becoming the record. The chain makes an edit to an existing record detectable; it does not
  authenticate authorship, and `templates/log-README.md` says exactly that rather than
  overselling it.
- **A superseded card keeps its citation seam closed.** When the owner changes their mind, the
  new card carries the statement's `[Q-NNN]` tag and the old one gets a `card-superseded` event.
  The old card stays Resolved and readable for its options, and `check-docs` stops demanding a
  citation for it while demanding that its successor exists. Never retire a card by deleting it,
  by editing its Answer, or by leaving a Resolved card that nothing cites.
- **Never renumber a spec section** after the first owner review. Append.
- **The output never references this skill**, its prompts, its templates or its process. Strip
  every `TEMPLATE NOTES` block when rendering and run the leakage greps of
  `stages/C-operationalize.md` Step C4 before every stop.
- **Never add scope.** A missing requirement whose absence matters is a card.
- **Copy mechanisms, not domain.** Templates carry the exemplar's mechanisms; the exemplar's
  tenancy model, entities and screens never leak into another product's pack.

## Files in this skill

| Path | Role |
| --- | --- |
| `reference/surfaces.md`, `decision-card.md`, `provenance.md` | the core mechanisms, read every session |
| `reference/elicitation-checklist.md` | the sweep Stage A runs so it does not under-elicit; amend it when implementation shows a surface was under-asked |
| `stages/A-elicit.md` … `D-review.md` | the rounds of each stage and where they stop |
| `stages/hunter.md` | prompts for the assumption hunter and the input auditor |
| `templates/` | near-verbatim and structural templates; each starts with `TEMPLATE NOTES` naming its placeholders |
| `templates/scripts/check-docs.py` | copied verbatim into the target as `scripts/check-docs.py` |
| `templates/scripts/lock-guard.py` | the lock policy: (diff, manifest) → violations; copied verbatim |
| `templates/scripts/unlock.sh`, `templates/UNLOCKS.md` | the unlock ceremony and its append-only log |
| `templates/.doc-locks` | the seed manifest, with the tiers each stage may promote |
| `templates/githooks/` | pre-commit, post-commit and the pre-receive mirror; transport only |
| `templates/scripts/eventlog.py` | the event log: chain primitives, event validation, the decisions projection |
| `templates/scripts/log-append.py`, `verify-chain.py` | the only sanctioned writer, and the chain check |
| `templates/scripts/rebuild-decisions.py`, `rebuild-questions.py` | the two projections, both thin over the shared renderer |
| `templates/decisions-seed.json` | the four regime records Stage B appends to a fresh log |
| `templates/log-README.md` | the log's own README: canonical form, and what the chain does not guarantee |
| `scripts/test-lock-guard.sh`, `scripts/test-decisions-log.sh`, `scripts/test-questions-log.sh` | acceptance tests of the lock layer and of the two streams, each in a throwaway repository |
| `scripts/test-check-docs.sh` | rule-level tests of `check-docs.py`, one minimal fixture per rule |
| `scripts/extract-normative.py` | lists normative statements with provenance; used after every writing round and as hunter input |
| `scripts/stage-detect.sh` | derives the stage from the target repository |

## At every stop

End the turn with a short report: what was written or changed (files), what the mechanical
passes said (`check-docs`, `extract-normative` counts), the cards awaiting the owner (per
surface, with IDs), and the one thing the owner does next. Nothing else.
