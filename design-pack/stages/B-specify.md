# Stage B — Specify

Entry: `stage-detect` said `B-fileset` or `B-write`. Every card with `Blocks: specification`
has an Answer. Read `reference/provenance.md` before the first round in a session.

Stage B writes the specification contract in rounds of at most four files. Each round ends
with a mechanical pass; the stage stops for the owner at B1 and at Exit, and whenever a round
produces a Blocking card.

## Round B1 — Propose the file set (only when `B-fileset`)

1. From the inputs and the answered cards, propose the domain files. Start from the roles that
   almost every product needs and drop or merge what the domain does not have:
   product scope and actors; architecture; domain model; the core lifecycle(s) of the main
   entity; content or catalogue; the core operational workflow; users and authorization; API
   contracts (if an API); UX and journeys (if a UI); notifications; security, privacy and
   retention; infrastructure and operations; testing and acceptance. Then the fixed tail in
   this order: traceability, decision-register, implementation-plan, agent-playbook. Two names
   are fixed because the templates cite them: the testing file is `NN-testing-acceptance.md`,
   and the architecture file is `NN-architecture.md` with `## 1. Repository layout` as its
   first section (`PLAN.md` and `AGENTS.md` cite `` `NN` §1 `` for the layout). The rest are
   `NN-kebab-name.md` as the domain suggests.
2. Present a table: number, file name (`NN-kebab-name.md`), purpose in one line, and which
   inputs and cards feed it. Keep domain files small enough to be read in one sitting (the
   exemplar's are 2.5–5 KB each). Fourteen domain files is a lot; six is fine for a small product.
3. Stop. The owner adjusts. Do not write any spec before approval.

## Round B2 — Foundations

1. Create the event log and seed the regime records. The log is the source of truth for agent
   decisions; `DECISIONS.md` is its projection and is never hand-written.
   - The log already exists from Stage A round A0; create it if this pack skipped Stage A:
     `mkdir -p <target>/.log && touch <target>/.log/events.jsonl`. An empty log is a valid genesis
     state: `seq` 1 links to 64 zeros, and `verify-chain` accepts it. Both streams share the one
     file and are told apart by `stream`.
   - Render and append the regime records of `${CLAUDE_SKILL_DIR}/templates/decisions-seed.json`
     in one command:
     `python3 ${CLAUDE_SKILL_DIR}/scripts/render-seed.py --root <target> --set DATE=<date> --set NN_TRACE=<NN> --set NN_REGISTER=<NN> --set NN_PLAN=<NN> --set NN_PLAYBOOK=<NN> --set REGISTER_CC_SECTION=6 --set D003_DECISION="..." --set D003_WHY="..." --set D003_ALTERNATIVES="..."`
     (the seed's `notes` say how D-003 reads with and without non-authoritative inputs). The tool
     refuses a placeholder it was not given a value for, and stops at the first record
     `log-append.py` refuses.
   - `python3 ${CLAUDE_SKILL_DIR}/templates/scripts/rebuild-decisions.py --root <target>`.
2. Render `specs/README.md` from its template with the approved file table. Status stays
   `Draft`. The technology baseline comes from the constraints (`[input]`), from answered cards
   (`[Q-NNN]`), or from defaults: a language, framework or library the inputs leave open is a
   `D-NNN` with alternatives (`reference/surfaces.md` §Never a card), while the hosting provider,
   the region and anything paid are `external` and are cards — normally raised in Stage A by the
   elicitation checklist, so B2 has nothing to stop for.
3. Run the mechanical pass (below).

## Round B3 — Domain files, at most four per pass (B3.1, B3.2, …)

Order: scope and actors first, then architecture, then domain model, then security, then the
rest in dependency order, testing and acceptance last among the domain files.

Writing rules for every file:

- Numbered `## N. Title` sections, never renumbered afterwards. Content appends.
- Normative language (`MUST`, `SHOULD`, `MAY`) for requirements; prose for explanation. Every
  normative statement ends with its provenance tag (`reference/provenance.md` §Form).
- Every `MUST` is testable: you can name the test, check or command that verifies it. If you
  cannot, rewrite it as prose or move the decision into a card. The testing file names the
  gates; the implementation plan names the package.
- `[input]` only for what the inputs say. `[Q-NNN]` for what an answered card says (or the
  recommendation of a deferred card, visibly provisional). `[D-NNN]` for a default from the
  ledger: append its `decision-added` event first (type `implementation`, dated today,
  alternatives from the ledger; its payload fields are in `reference/events-and-rules.md`, which
  is where every event's fields and every `--only` rule name live) and rebuild the projection,
  then write the statement. Never add a
  `D-NNN` by editing `DECISIONS.md`; `check-docs` compares that file to the log and fails on any
  difference. `[inferred]` for anything else, temporarily.
- Nothing not in the inputs or a card is added as MVP. A missing requirement whose absence
  matters is a card, never a default.
- Cite other specs as `` `NN` §M `` and keep the citations resolving.
- Style: a one-line purpose under the title when needed, then numbered sections of short
  bullets; tables for enumerations (entities and their fields, roles and permissions, events
  and their channels); a mermaid diagram where a state machine, a dependency graph or an
  entity relationship is clearer drawn than written; no marketing prose; 2.5–5 KB per file.

Mechanical pass after every round:

1. `python3 ${CLAUDE_SKILL_DIR}/scripts/extract-normative.py --specs <target>/specs --untagged`
   must list nothing. Tag what it lists.
2. `python3 ${CLAUDE_SKILL_DIR}/scripts/extract-normative.py --specs <target>/specs | grep -P '\tinferred\t'`
   lists every `[inferred]`. For each: does it touch a surface (`reference/surfaces.md`)?
   Yes: write a card, tag the statement `[Q-NNN]`, treat the statement as the recommendation.
   No: write a `D-NNN`, retag `[D-NNN]`.
3. Every new card opens Blocking, so a round that raises one stops: present the new cards
   (Stage A batch form), wait, record the owner's answers or deferrals as events, rebuild, then
   continue. A card the owner has not seen is never deferred by the skill; where the answer
   only matters later, the recommendation says so and the owner defers in one word.
4. `python3 ${CLAUDE_SKILL_DIR}/templates/scripts/check-docs.py --root <target> --quiet --only citations,markers,decisions,cards,register,provenance,normative-tagged,chain-intact,projection-fresh`:
   the rules that can hold before the root documents exist; every failure it reports is
   actionable. `chain-intact` and `projection-fresh` must pass from B2 on: a failure there means
   an entry was hand-written or a log line was edited. The full run is Stage C's.
5. Report in one paragraph: files written, statements by provenance, cards created, defaults
   recorded. Continue to the next round in the same turn unless a stop was triggered.

## Round B4 — Register and card resolution

1. Every answered card now has at least one statement tagged with its ID; verify with
   `grep -rn 'Q-NNN' <target>/specs`. Append a `card-resolved` event for each such card and
   rebuild the projection; that is what moves it to `## Resolved`, and the whole card is rendered
   there from the log rather than copied. Deferred cards stay Open.
2. Render the decision register from its template. Each bullet compresses one or more statements
   that exist in the domain files, keeps their tag, and cites only `[input]` or Resolved
   `[Q-NNN]`. Group by surface. Section 6 verbatim.
3. Mechanical pass. `check-docs` must now show `register` and `cards` passing.

## Round B5 — Plan, playbook, product traceability

1. Implementation plan from its template. Phase 0 as the template fixes it (FND-01 is the
   command contract; FND-03 and FND-04 only when there is an API or a UI). Domain phases in
   dependency order, each with Goal, packages with stable IDs and outcome bullets, and Exit
   criteria a command or test demonstrates.
   Then give every package its six characteristics: the data the loop's prompt-selection table
   runs on (`templates/AGENTS.md` §Prompt selection), and the data an orchestrator schedules by:
   - `python3 ${CLAUDE_SKILL_DIR}/templates/scripts/check-docs.py --root <target> --task all`
     prints, per package, the derived `Surfaces` and `Touches red line`. Copy both onto the
     package verbatim, one line each. They are derived from the sections the package cites, so
     they are never judged and never written from memory; `AGENTS.md` does not exist yet, so
     `Touches red line` reads `no` for every package and Stage C recomputes it once the red lines
     are compiled.
   - Set `Contract change:`, `File surface:` and `Lane:` per package yourself. `Contract change`
     is `yes` when the package defines or modifies an interface, API or schema contract, else
     `no`. `File surface` is the directories or modules the package may change, as the
     architecture spec's layout spells them. `Lane` is one of the lanes the plan's parallelization
     section lists, verbatim. All three are implementation judgements, not surface questions, so
     they are recorded rather than asked: append one `decision-added` event (type
     `implementation`) naming the packages that are `yes`, the lane assignment and why, with the
     alternatives weighed, and rebuild the projection.
   - Set `Depends on:` per package: the packages **of the same phase** that must be `done` before
     it starts, or `—`. Phase order is already the plan's, so a package of another phase is never
     listed. One pair is derived, not judged: a package citing a section that a
     `Contract change: yes` package of its phase also cites depends on that package, and
     `task-policy` names the pair if it is missing. Any further dependency is your judgement;
     record it, with its reason, in the same `decision-added` as the lanes. An orchestrator
     reads this field instead of inferring an order, and an inferred order is a decision an
     agent made that nobody recorded.
   - **A package whose file surface spans more than one lane is a package to split**, at the seam
     the lanes already name, or to explain in that same decision. This is the only place the plan
     has a size at all: a package nobody can bound is a session nobody can finish, and the
     exemplar's own plan carried packages three subsystems wide with nothing to notice it. How
     wide is too wide is a judgement about the product, so it is a sentence here and not an
     assertion; what the gate holds is that the fields exist and that the lane is one the plan
     defines.
   - Re-run `--task all` and check each line against the package; `check-docs`'s `task-policy`
     rule fails the build on any disagreement, so a value copied wrong does not survive Stage C. For every Open card whose `Blocks:` still names a
   `Phase N` — a card the owner deferred in Stage A, before packages existed — append a
   `card-deferred` event carrying the package ID that the answer changes, and rebuild: this
   refines the target of the owner's deferral, it does not defer anything, and the card's
   `Blocks:` is data in the log, not a line to edit.
2. Agent playbook from its template, near-verbatim; regenerate the example prompt from a real
   Phase 1 or Phase 2 package.
3. Product-intent traceability from its template: one row per requirement in the inputs, in the
   owner's words where possible, with the spec that implements it and its scope status. A row
   whose status is not fixed by input or card is a scope card.
4. Mechanical pass.

## Exit

1. Full `check-docs` and `extract-normative` reports.
2. Report: files and sizes, statements by provenance per file, `[inferred]` remaining (must be
   zero, or list them with the card or decision that will clear them), cards Resolved and Open.
3. State that Stage C compiles the operating layer and needs no owner input, and that the owner
   reads the whole pack at Stage D.
4. Stop.
