# Assumption hunter and input auditor

Two prompts for fresh agent instances (Agent tool, `general-purpose`). They get no
conversation history. Substitute `<target>`, `<scratch>` and `<date>` before sending.
Each agent writes one file and reports its count; nothing else.

## Hunter

```text
You are reviewing a specification pack for unratified decisions. You have one mandate and
no other.

Read <target>/specs/README.md (the section "Provenance" defines the tags), then
<scratch>/normative.md, which lists every normative statement in <target>/specs/ with its
file, section, line and provenance tag. Open the spec files themselves whenever you need the
statement's context.

A statement "touches a surface" when its plausible alternatives would change one of:
- data: entities, relationships, identifiers, what is stored, for how long
- security: who can access what, authentication model, tenancy or ownership boundary, trust boundaries
- scope: what is MVP, what is Future, what is excluded
- external: money, third parties, jurisdiction, legal or regulatory obligations, externally mandated retention
- ux: primary navigation structure, critical user journeys, brand behaviour

For every statement whose provenance is not [input] and not [Q-NNN] (that is: [D-NNN],
[inferred], or no tag) and which touches at least one surface, write a decision card in
exactly this shape:

### Q-XXX — <title>
- Surface: <data|security|scope|external|ux>
- Source: `<NN-file.md>` §<section> line <line>: "<the statement, quoted>"
- Question: <one sentence the owner can answer by choosing an option>
- Options:
  - A) <the statement as written> → effect on <surface>: <concrete consequence>
  - B) <the plausible alternative> → effect on <surface>: <concrete consequence>
- Recommendation: A, because <the pack currently assumes it; one sentence>
- Blocks: <the earliest work package in <target>/specs/*-implementation-plan.md whose outcome
  implements the statement; `specification` only when the statement is in the register or the
  spec map>

Use Q-XXX literally; IDs are assigned later. Do not fix anything. Do not evaluate whether
the statement is a good decision; the owner does that. Do not skip a statement because it
seems obvious, reasonable or standard; obviousness is not the test, surface is. Do not report
statements tagged [D-NNN] that touch no surface (tooling, naming, layout, local ports).

Write all cards to <scratch>/hunter-findings.md. If there are none, write the single line
"No findings." Reply with one line: the number of cards written.
```

## Input auditor

```text
You are auditing provenance claims in a specification pack. You have one mandate and no other.

Read <target>/docs/inputs/README.md to learn which files are authoritative inputs, then read
every authoritative input file under <target>/docs/inputs/. Then read <scratch>/normative.md,
which lists every normative statement in <target>/specs/ with its provenance tag.

For every statement tagged [input], find the passage in the authoritative inputs that states
it. Paraphrase counts; a statement that merely follows logically from the inputs does not,
and a statement the inputs contradict certainly does not.

Write to <scratch>/input-audit.md one line per statement you could NOT support:

- `<NN-file.md>` §<section> line <line>: "<statement>" — <not found | contradicted by
  <input file>: "<quote>" | only implied by <input file>: "<quote>">

Do not fix anything. Do not judge whether the statement is sensible. If every [input] is
supported, write the single line "All [input] statements are supported." Reply with one
line: the number of unsupported statements.
```
