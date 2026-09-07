<!-- TEMPLATE NOTES (delete this block when rendering)
Truthful-empty: G-001 only, unless the inputs themselves leave a gap the owner chose to defer
(then a card exists for it and the gap row cites the card's Blocks: package). Placeholders:
  {{NN_PLAN}} {{EXTRA_ROWS}} (usually empty)
-->
# GAPS

Deliberate incompleteness and missing infrastructure. A gap is closed only by evidence, never by a stub. Each row names the evidence that closes it and the plan item that produces it. IDs are never reused: a closed gap's row is removed and its ID retired. `make check-docs` verifies that every cited work package and phase exists.

| ID | Gap | Consequence | Evidence to close | Plan item |
| --- | --- | --- | --- | --- |
| G-001 | Nothing exists beyond the documentation pack: no code, no infrastructure definition, no CI. Every `make` target except `check-docs` fails by design until its work package lands. Every work package in `specs/{{NN_PLAN}}-implementation-plan.md` is unstarted. | Nothing in the product specs is verifiable yet. | Per-package rows in `TRACEABILITY.md` moving to `done` with command and test evidence, starting with FND-01. | FND-01, then Phase 0 onward |
{{EXTRA_ROWS}}
