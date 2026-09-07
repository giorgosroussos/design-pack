# The decision card

The skill may not ask the owner anything that does not fit this shape. The
card is the five-surface filter made operational: if "effect on surface"
cannot be filled for at least one option, the question is not the owner's.

## Shape

```
### Q-NNN — <title>
- Surface: data | security | scope | external | ux
- Source: <requirement text, input file and location, mockup artboard, or the gap that raised it>
- Question: <one sentence>
- Options:
  - A) <option> → effect on <surface>: <concrete consequence>
  - B) <option> → effect on <surface>: <concrete consequence>
  - C) <option> → effect on <surface>: <concrete consequence>   (optional)
- Recommendation: <A|B|C>, because <one or two sentences>
- Blocks: <specification | phase N | WORK-PACKAGE-ID>
- Answer: <A|B|C|text> (<date>; "recommendation accepted" when the owner said so)   ← added when answered
```

Rules for filling it:

- **Surface** is exactly one of the five values, lower case, and names the surface of the *question*, not of its downstream consequences: whether a capability exists at all is `scope` even if building it would add an entity; how a journey is navigated is `ux` even if it changes which endpoints exist. When the question itself sits on two surfaces, take the earliest in the order data → security → scope → external → ux, and name the second in the consequences.
- **Source** must be locatable: a quoted phrase and its file, or an artboard ID, or "absent from the inputs" when the gap itself is the source.
- **Question** is one sentence and is answerable by choosing an option.
- **Options** are mutually exclusive and cover the plausible space. Each consequence names the surface and states what becomes true in the product, not what becomes true in the code. "→ effect on data: a second entity with its own retention" is right; "→ needs another table" is not.
- **Recommendation** is mandatory. It is what the skill would have done silently if it were allowed to. Making it explicit is what turns "the agent decided" into "the owner accepted".
- **Blocks** names what cannot proceed without the answer: `specification` when the spec pack cannot be written coherently either way (typical for data and security cards), otherwise the earliest phase or work package whose acceptance depends on the answer.
- **Answer** is appended, never edited: it is an event in the log. If the owner changes their mind later, a new card supersedes the old one, and the old Answer stays where it is.

## Ordering and batches

Cards are presented grouped by surface in dependency order: data first (everything hangs on it), then security, scope, external, ux last. Within a surface, a card whose answer changes the options of another card comes first.

A batch is one surface group, at most eight cards. If a surface has more than eight, split at a dependency boundary and say so. Each batch is presented in full, in the conversation, in this form:

```
Batch <n> of <m> — <surface> (<k> cards)

<the cards, in order>

You can answer per card ("Q-003 B, Q-004 A"), or "accept recommendations" for
the whole batch, or "accept recommendations except Q-004: B". Cards you do not
answer now stay open with their Blocks: field and are raised again before the
phase they block.
```

## Recording answers

`QUESTIONS.md` is a projection of the `questions` stream of the event log. The shape above is what
it renders; the way it is written is an appended event, never an edit. Each of these is
`scripts/log-append.py --stream questions --type <event>` followed by `make rebuild-questions`.

- Per-card answer: `card-answered` with the answer and the date. It renders as `- Answer: B (2026-09-03)`.
- "Accept recommendations for the batch": one `card-answered` per card in the batch, with `recommendation_accepted` set, which renders as `- Answer: B (2026-09-03; recommendation accepted)`. The provenance tag in the spec then reads `[Q-NNN, recommendation accepted]`. The acceptance is the owner's recorded decision; the recommendation was the skill's.
- Deferred: no `card-answered`. A `card-deferred` carrying the phase or package the answer changes moves the card to `## Open` and sets its `Blocks:`. The spec text that depends on it is written from the recommendation and tagged `[Q-NNN]`, so the provisional status is visible wherever the statement is read. It may not enter the locked register until the card is Resolved.
- Resolved: `card-resolved`, appended when the spec text that carries the card's `[Q-NNN]` tag exists (Stage B), not when the answer is given. `check-docs` asserts that every Resolved card is cited by a statement.
- Changed mind: a new card, then `card-superseded` on the old one. The old card stays Resolved and keeps its answer and its options; the statement's tag moves to the new card. `check-docs` expects the citation on the successor and stops requiring one on the superseded card, which is why supersession has to be an event rather than a hand edit.

## The "no third category" rule

Every candidate decision ends in exactly one of two places: a card in `QUESTIONS.md` or a `D-NNN` in `DECISIONS.md`. There is no "important, but I will decide it and mention it in the summary". A decision mentioned in a chat message and nowhere else is a silent decision.
