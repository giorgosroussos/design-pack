<!-- TEMPLATE NOTES (delete this block when rendering)
Written at the very start of Stage A, before any card. This is the intake statement made durable:
what was received, and what is authoritative. Renders to docs/inputs/README.md. Raw inputs are
copied verbatim next to it (subfolders allowed: requirements/, mockups/, transcripts/, prior/).
Placeholders:
  {{DATE}}
  {{ROWS}}       one row per input file: File | Received | Kind (requirements, constraints,
                 mockup, competitor reference, prior draft, transcript) | Authority
                 Authority is one of:
                   authoritative — requirements source; statements from it are tagged [input]
                   authoritative (constraints) — fixes stack, deployment, jurisdiction, budget
                   non-authoritative — direction only; specs win; conflicts are cards Q-NNN..Q-MMM
  {{CONFLICT_PARAGRAPH}}  for each non-authoritative input: what it is direction for, what in it
                 the specs exclude or do not define, and the cards that hold each conflict.
                 If there is no non-authoritative input: "No non-authoritative input was received."
  {{ABSENT_PARAGRAPH}}    what the inputs do not cover that the pack needs (constraints absent,
                 areas silent), and the cards that ask for it.
-->
# Inputs

Raw material the specification pack was written from, received {{DATE}}. Files here are copied verbatim and never edited; if the owner supplies a revision, it is added as a new file with its date.

| File | Received | Kind | Authority |
| --- | --- | --- | --- |
{{ROWS}}

## What each authority level means

- **Authoritative.** A requirements source. Every normative statement in `specs/` that restates it carries the `[input]` tag. Where two authoritative inputs disagree, the disagreement is a question card in `QUESTIONS.md`, not a choice.
- **Authoritative (constraints).** Fixes the stack, deployment, jurisdiction, budget or existing systems. Statements restating it are `[input]`. Constraints the inputs do not fix are cards.
- **Non-authoritative.** Direction only: look, tone, layout, examples of what a competitor does, an earlier draft. Specifications win on behaviour. Each behavioural conflict between such an input and the requirements is a card, and the input is never cited as the provenance of a normative statement.

## Non-authoritative inputs and their conflicts

{{CONFLICT_PARAGRAPH}}

## What the inputs do not cover

{{ABSENT_PARAGRAPH}}
