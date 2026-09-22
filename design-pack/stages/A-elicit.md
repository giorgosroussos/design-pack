# Stage A — Elicit

Entry: `stage-detect` said `A-intake`, `A-extract` or `A-cards`. Read `reference/surfaces.md`,
`reference/decision-card.md` and `reference/elicitation-checklist.md` before the first
round of this stage in a session.

Every card opens Blocking (`Blocks: specification`; `log-append` refuses anything else) and
becomes Open only when the owner defers it. Stage A therefore ends when no Blocking card lacks
an `Answer:`, which is the same as saying every card was presented and either answered or
deferred; `stage-detect` reads exactly that. It runs in rounds; every round ends by stopping
and waiting for the owner.

## Round A0 — Intake (only when `A-intake`)

1. Collect the inputs. Files the owner named are copied verbatim under `docs/inputs/<kind>/`
   (`requirements/`, `constraints/`, `mockups/`, `references/`, `prior/`, `transcripts/`).
   Text pasted in the conversation is saved as a file with today's date in its name.
   Nothing is edited.
2. Classify each input as authoritative, authoritative (constraints) or non-authoritative
   (see `templates/docs-inputs-README.md` for the definitions). Requirements and product
   intent are authoritative. Mockups, competitor references and prior drafts are
   non-authoritative unless the owner says otherwise.
3. Render `docs/inputs/README.md` from the template. Create the event log and its projection:
   `mkdir -p <target>/.log && touch <target>/.log/events.jsonl` (an empty log is a valid genesis
   state), then `python3 ${CLAUDE_SKILL_DIR}/templates/scripts/rebuild-questions.py --root <target>`, which
   writes `QUESTIONS.md` with its sections empty. `QUESTIONS.md` is a projection from here on and
   is never edited by hand: every card, answer, deferral, resolution and supersession is an event.
4. State in the conversation, in this order: what was received; what is treated as
   authoritative and why; what is non-authoritative and what it will be used for; what the
   inputs are silent on (stack, deployment, jurisdiction, budget, existing systems).
5. Stop. Ask the owner to confirm or correct the authority levels. Do not extract yet. In the
   same message, say this once: the skill's pre-approved commands last for this turn only, so
   from the next reply on every command and file write will ask for permission unless the owner
   allows the skill's patterns for the session. Offer the project-local form — "say *allow* and
   I write `.claude/settings.local.json` in this directory from the skill's template, with the
   same patterns as the skill's own list; it is not committed" — and name the alternative, the
   same rules in `~/.claude/settings.json` for every project (the install notes show them). On
   *allow*, render `templates/claude-settings.local.json` with `{{SKILL_DIR}}` = the skill's
   directory into `<target>/.claude/settings.local.json` at the start of the next round, and
   nothing else changes. Without it, the run still works; it just asks.

## Round A1 — Extract (when `A-extract`)

1. Read every input in full.
2. Build the candidate list in the scratchpad (not in the repository): every statement,
   silence or contradiction that requires a choice. Include contradictions between inputs
   and every behavioural conflict between a non-authoritative input and the requirements.
3. Run the sweep in `reference/elicitation-checklist.md` against the inputs and add the
   candidates it produces, including the always-present cards when the inputs are silent.
4. For each candidate apply the procedure in `reference/surfaces.md` §The procedure:
   - a fact the input states: no card, remember it as `[input]` for Stage B;
   - touches a surface: append a `card-opened` event (payload fields in
     `reference/decision-card.md`; the shape of the card is unchanged, only the way it is
     written) with `Blocks: specification`, always: a card is Blocking until the owner answers
     it or defers it. Where the answer only matters from a later phase on, say so in the
     recommendation ("can be deferred to Phase N"), so the owner can defer it in one word;
   - touches none: add it to the defaults ledger in the scratchpad (decision, alternatives,
     why). Stage B turns each into a `D-NNN` when it becomes a spec statement.
5. Assign IDs in the order data, security, scope, external, ux, so the cards of this round read
   in dependency order, and append the events in that order: the projection renders cards in
   the order they were opened. Cards raised later (Stage B, the hunter) take the next free ID
   whatever their surface; the index line carries the surface, so the order is still readable. One event per card:
   `python3 ${CLAUDE_SKILL_DIR}/templates/scripts/log-append.py --root <target> --stream questions --type card-opened --payload-file -`
   with the payload on stdin (`id`, `title`, `surface`, `source`, `question`, `options` as a JSON
   array, `recommendation`, `blocks: specification`; every event's fields are in
   `reference/events-and-rules.md`, so no script is opened to find one) — or, for a whole round, one JSON array of
   such payloads in a file written to the scratchpad and passed with `--payload-file <file>`:
   every element is validated first and the batch is appended all or nothing. The tool refuses a
   card whose options carry no consequence, whose surface is not one of the five, or that tries
   to open as anything but Blocking.
6. `python3 ${CLAUDE_SKILL_DIR}/templates/scripts/rebuild-questions.py --root <target>`. The index and the
   Blocking, Open and Resolved sections are generated: every new card sits under `## Blocking`;
   a `card-deferred` event moves it to `## Open`; nothing places it by hand.
7. Report the counts per surface and the number of batches. Then present batch 1 (below)
   in the same turn.

## Rounds A2… — Present a batch, record answers

1. A batch is one surface group in the order data, security, scope, external, ux, at most
   eight cards. Present it exactly in the form given in
   `reference/decision-card.md` §Ordering and batches, cards in full.
2. Stop. Wait for the owner.
3. Record answers as events, one `card-answered` per card, then rebuild
   (`reference/decision-card.md` §Recording answers). Every `card-answered` needs `answer` (the
   letter of the chosen option) and `date`; "Accept recommendations" is one event per card of the
   batch with the recommended letter as the answer and `--set recommendation_accepted=true` as
   well. A card the owner explicitly
   defers gets no answer: append `card-deferred` with a `blocks` naming the phase or package the
   answer changes (`Phase N` for now; Stage B refines it to a package ID), which moves it to
   `## Open`; say so in the report. Deferral is the owner's act only: the skill never appends
   `card-deferred` on its own initiative.
4. If an answer invalidates or creates another card, write it now, in the same surface group,
   with the next free ID. It joins the next batch.
5. Present the next batch. When every surface group is done, go to Exit.

## Exit

When no Blocking card lacks an Answer:

1. Run `python3 ${CLAUDE_SKILL_DIR}/templates/scripts/check-docs.py --root <target> --quiet --only cards,provenance,chain-intact,projection-fresh`:
   the rules that can hold before any other document exists. Fix every failure it reports.
2. Report: cards per surface (answered, deferred), the deferred cards with what they block, the
   size of the defaults ledger. State that Stage B starts on the owner's word and what its first
   round produces (a proposed file set, nothing written).
3. Stop.

## Rules that hold throughout Stage A

- Never answer a card yourself, not even to "get the batch out". An unanswered card is a card.
- Never present a card without a Recommendation. If you cannot recommend, the options are
  not yet concrete enough; rewrite them.
- Never merge two questions into one card to shorten the batch.
- A candidate whose only plausible answers differ in code but not in product behaviour is a
  default, not a card, however important it feels.
- When the owner asks "what would you do?", the answer is the Recommendation already on the
  card. Do not decide in the conversation; record on the card.
