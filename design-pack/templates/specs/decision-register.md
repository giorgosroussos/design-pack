<!-- TEMPLATE NOTES (delete this block when rendering)
Locked decision register. Written LAST in Stage B, from tagged statements only.
Rules:
  - Every bullet is a compression of a statement that exists somewhere in the domain specs
    with the same tag. Nothing appears here first.
  - Only `[input]` and `[Q-NNN]` (optionally `, recommendation accepted`). A `[Q-NNN]` may be
    cited only when the card is under Resolved in QUESTIONS.md. Open cards stay in the domain spec.
  - Grouped by the five surfaces, in this order. An empty surface keeps its heading and the line
    "No locked decision on this surface." so numbering never shifts.
  - Section 6 is verbatim.
Placeholders: {{DATA_BULLETS}} {{SECURITY_BULLETS}} {{SCOPE_BULLETS}} {{EXTERNAL_BULLETS}} {{UX_BULLETS}}
              {{PRODUCT_NAME}}
-->
# Locked Decision Register

Each bullet below is an owner decision: stated in the requirements (`[input]`) or made by answering a question card (`[Q-NNN]`, see `QUESTIONS.md`). Nothing else appears here; `make check-docs` fails on any other provenance. Bullets are compressions of statements in the domain specifications, grouped by the surface they fix.

## 1. Data

{{DATA_BULLETS}}

## 2. Security

{{SECURITY_BULLETS}}

## 3. Scope

{{SCOPE_BULLETS}}

## 4. External commitments

{{EXTERNAL_BULLETS}}

## 5. Product identity and UX

{{UX_BULLETS}}

## 6. Change control

These decisions are implementation constraints. A proposed change requires:

1. a short ADR describing the problem;
2. alternatives and security/data/scope impact;
3. migration and testing implications;
4. Product Owner approval before code changes.

The ADR is a `DECISIONS.md` entry of type `adr` carrying `Owner approval: pending` until the owner grants or rejects it. Agents MUST NOT reopen decisions merely because a different framework or pattern is familiar. Small implementation details may be decided locally if they preserve the locked behavior and are recorded in `DECISIONS.md`.
