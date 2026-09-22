---
name: design-pack
description: Generate the design documentation pack that an implementation agent works from - a frozen specification contract, an operating layer (AGENTS.md, pointers, loop prompts, command contract) and living state documents - by eliciting the owner's decisions through decision cards, in rounds, never in one shot. Design phase only; writes no code.
argument-hint: "[target-dir]"
disable-model-invocation: true
allowed-tools:
  # This pre-approval lasts ONE turn: Claude Code clears it when the owner sends the next
  # message, and this skill stops for the owner many times. Stage A round A0 therefore offers
  # the owner the same patterns for the session (templates/claude-settings.local.json, or the
  # user's own settings; see the install notes). scripts/test-allowed-tools.sh keeps the two
  # listings identical.
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
  # the skill's own tools
  - Bash(bash ${CLAUDE_SKILL_DIR}/scripts/*)
  - Bash(python3 ${CLAUDE_SKILL_DIR}/scripts/*)
  - Bash(python3 ${CLAUDE_SKILL_DIR}/templates/scripts/*)
  # the copied tools, run inside the target
  - Bash(python3 scripts/*)
  - Bash(make check-docs)
  - Bash(make check-locks)
  - Bash(make verify-chain)
  - Bash(make rebuild-decisions)
  - Bash(make rebuild-questions)
  - Bash(make install-hooks)
  - Bash(make unlock *)
  - Bash(make brief *)
  # Stage A intake and Stage C assets: every subcommand of a `&&` or a pipe must match on its own
  - Bash(cd *)
  - Bash(mkdir *)
  - Bash(touch *)
  - Bash(cp *)
  - Bash(chmod *)
  - Bash(git config core.hooksPath*)
  - Bash(git add *)
  - Bash(git commit *)
  - Bash(grep *)
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
2. Read the matching stage file and follow it: `A-intake`, `A-extract`, `A-cards` → `stages/A-elicit.md`;
   `B-fileset`, `B-write` → `stages/B-specify.md`; `C` → `stages/C-operationalize.md`;
   `D` → `stages/D-review.md`; `frozen` → say so, point at the amendment regime in the target's
   `AGENTS.md`, offer only a re-run of the hunter (Stage D round D1) on request, and stop.
3. Read `reference/surfaces.md`, `reference/decision-card.md` and `reference/provenance.md`
   once per session before any stage work. They are short and they are the core.
   `reference/events-and-rules.md` is a **lookup, not a session read**: open it when you need a
   payload field or a rule name, and never read a script to find one. A stage that needed a field
   and went looking in `templates/scripts/` is a defect in that stage, not in the agent.
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
   register may hold only `[input]` and Resolved `[Q-NNN]`; `check-docs` enforces it, and
   enforces the tag itself (`normative-tagged`) and that no `[inferred]` survives the
   freeze (`inferred-zero`), in the generated pack, for as long as it lives.
4. **The assumption hunter** (`stages/hunter.md`): a fresh agent with one mandate reads the
   pack and writes every surface-touching statement that is not `[input]` or `[Q-NNN]` as a
   card. It fixes nothing and judges nothing.

Deferral is allowed: a card may stay Open with `Blocks:` set, and the loop's third prompt
raises it before that phase. But every card opens Blocking and only the owner's word defers
it (`card-deferred`); the skill never defers a card on its own. Silent decision is the only
unacceptable state.

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
  the pre-receive mirror on the remote, which `--no-verify` cannot reach. What the remote holds
  is that no locked change lands without a recorded reason for that path; the reason is
  self-asserted, so the ceremony is an audit trail, not an approval gate, and the pack's
  documents say so rather than more. Tiers only go up: the
  guard judges a change with the manifest before it and refuses any change that lowers a tier,
  and the manifest, the guard and the hooks are hard-locked from the first commit. A hard-locked file
  changes only through `make unlock PATH=... REASON="..."`, recorded in `UNLOCKS.md` and good
  for exactly one commit. Tiers are promoted, never assumed: a file is locked when the stage
  that legitimately writes it is over, which is why `specs/` and `QUESTIONS.md` are free until
  the freeze promotes them (`stages/D-review.md` D4).
- **One home per rule.** `AGENTS.md`, `CLAUDE.md`, the playbook and the prompts point at each
  other; they do not repeat each other.
- **One home per kind of knowledge.** `specs/` says what the product must do; a `D-NNN` says why a
  judgement went one way; `docs/layers/<PACKAGE>.md` says what the delivered code now does that a
  later slice must not get wrong, and carries that session's handoff; `docs/gotchas.md` says what
  the tooling does that an agent cannot predict. `AGENTS.md` indexes the layer notes and never
  holds one — a section per package there is read by every session forever, which is how an entry
  point grows past the point where anyone reads it, and `check-docs` (`layer-notes`) refuses it.
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
- **Never edit the skill.** Nothing under `${CLAUDE_SKILL_DIR}` is written, edited or patched
  during a run, whatever a check reports: a defect in a template or a script is a finding for
  the stop's report, quoted with file and line, and the run continues with the skill as it is.
  The target gets copies; the skill stays the reference.
- **Copy mechanisms, not domain.** Templates carry the exemplar's mechanisms; the exemplar's
  tenancy model, entities and screens never leak into another product's pack.

## Files in this skill

| Path | Role |
| --- | --- |
| `reference/surfaces.md`, `decision-card.md`, `provenance.md` | the core mechanisms, read every session |
| `reference/elicitation-checklist.md` | the sweep Stage A runs so it does not under-elicit; amend it when implementation shows a surface was under-asked |
| `reference/events-and-rules.md` | looked up, not read every session: every event's payload fields, what each renders as, and the `check-docs` rule names `--only` takes |
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
| `templates/decisions-seed.json` | the five regime records Stage B appends to a fresh log |
| `templates/claude-settings.local.json` | the skill's command patterns as a session-long permission grant, offered to the owner at the intake stop |
| `templates/log-README.md` | the log's own README: canonical form, and what the chain does not guarantee |
| `templates/docs-layers-README.md` | `docs/layers/`: one note per delivered work package, the shape of a note, and the rule that `AGENTS.md` indexes them and never holds one |
| `templates/gotchas.md` | `docs/gotchas.md`: what the tooling does that an agent cannot predict, empty until a session learns it |
| `scripts/test-lock-guard.sh`, `scripts/test-decisions-log.sh`, `scripts/test-questions-log.sh` | acceptance tests of the lock layer and of the two streams, each in a throwaway repository |
| `scripts/test-check-docs.sh` | rule-level tests of `check-docs.py`, one minimal fixture per rule |
| `scripts/test-task-policy.sh` | the `task-policy` rule and the `--task` reader over a fixture pack: derived characteristics, the policy table, and `blocked-by` as a live read |
| `scripts/test-render.sh` | renders every template for a fixture product and proves the result passes the whole gate, the lock layer and `stage-detect` |
| `scripts/test-allowed-tools.sh` | every shell command the stage files instruct matches a `Bash(...)` pattern of this file's `allowed-tools`, subcommand by subcommand |
| `scripts/test-stage-detect.sh` | walks a target through every state and asserts `stage-detect` names each one |
| `scripts/extract-normative.py` | lists normative statements with provenance; used after every writing round and as hunter input |
| `scripts/render-seed.py` | renders `templates/decisions-seed.json` and appends the regime records through `log-append.py`, in one command |
| `scripts/stage-detect.sh` | derives the stage from the target repository |

## At every stop

End the turn with a short report: what was written or changed (files), what the mechanical
passes said (`check-docs`, `extract-normative` counts), the cards awaiting the owner (per
surface, with IDs), and the one thing the owner does next. Nothing else.
