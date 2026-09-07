# Stage A — Elicit

Entry: `stage-detect` said `A-intake` or `A-cards`. Read `reference/surfaces.md`,
`reference/decision-card.md` and `reference/elicitation-checklist.md` before the first
round of this stage in a session.

Stage A ends when no card whose `Blocks:` is `specification` lacks an `Answer:`. It runs
in rounds; every round ends by stopping and waiting for the owner.

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
   `mkdir -p <target>/.log && : > <target>/.log/events.jsonl` (an empty log is a valid genesis
   state), then `python3 ${CLAUDE_SKILL_DIR}/templates/scripts/rebuild-questions.py --root <target>`, which
   writes `QUESTIONS.md` with its sections empty. `QUESTIONS.md` is a projection from here on and
   is never edited by hand: every card, answer, deferral, resolution and supersession is an event.
4. State in the conversation, in this order: what was received; what is treated as
   authoritative and why; what is non-authoritative and what it will be used for; what the
   inputs are silent on (stack, deployment, jurisdiction, budget, existing systems).
5. Stop. Ask the owner to confirm or correct the authority levels. Do not extract yet.

## Round A1 — Extract (first `A-cards` round)

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
     written), with `Blocks: specification` for data and security cards, and for scope cards that
     move something across the MVP boundary; otherwise `Blocks:` the earliest phase or package the
     answer changes (name it `Phase N` for now; Stage B replaces it with a package ID);
   - touches none: add it to the defaults ledger in the scratchpad (decision, alternatives,
     why). Stage B turns each into a `D-NNN` when it becomes a spec statement.
5. Assign IDs in the order data, security, scope, external, ux, so IDs read in dependency order,
   and append the events in that order: the projection renders cards in the order they were
   opened. One event per card:
   `python3 ${CLAUDE_SKILL_DIR}/templates/scripts/log-append.py --root <target> --stream questions --type card-opened --payload-file -`
   with the payload on stdin (`id`, `title`, `surface`, `source`, `question`, `options` as a JSON
   array, `recommendation`, `blocks`). The tool refuses a card whose options carry no consequence
   or whose surface is not one of the five.
6. `python3 ${CLAUDE_SKILL_DIR}/templates/scripts/rebuild-questions.py --root <target>`. The index and the
   Blocking, Open and Resolved sections are generated: a card sits under `## Blocking` when its
   `blocks` is `specification`, otherwise under `## Open`, and nothing places it by hand.
7. Report the counts per surface and the number of batches. Then present batch 1 (below)
   in the same turn.

## Rounds A2… — Present a batch, record answers

1. A batch is one surface group in the order data, security, scope, external, ux, at most
   eight cards, blocking cards first. Present it exactly in the form given in
   `reference/decision-card.md` §Ordering and batches, cards in full.
2. Stop. Wait for the owner.
3. Record answers as events, one `card-answered` per card, then rebuild
   (`reference/decision-card.md` §Recording answers). "Accept recommendations" is
   `--set recommendation_accepted=true` on each card of the batch. A card the owner explicitly
   defers gets no answer: append `card-deferred` with a `blocks` naming the phase, which moves it
   to `## Open`; say so in the report.
4. If an answer invalidates or creates another card, write it now, in the same surface group,
   with the next free ID. It joins the next batch.
5. Present the next batch. When every surface group is done, go to Exit.

## Exit

When no Blocking card lacks an Answer:

1. Run `python3 ${CLAUDE_SKILL_DIR}/templates/scripts/check-docs.py --root <target> --quiet`
   and ignore failures about files that do not exist yet; fix any failure about `QUESTIONS.md`.
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
