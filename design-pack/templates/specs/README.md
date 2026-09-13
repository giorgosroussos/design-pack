<!-- TEMPLATE NOTES (delete this block when rendering)
Spec map. Rendered in Stage B round 1, right after the owner approves the file set.
Placeholders:
  {{PRODUCT_NAME}}            short product name
  {{PRODUCT_STATEMENT}}       one or two sentences, what it is and what it is not, tagged
  {{PRODUCT_PARAGRAPH}}       who it serves, the core loop, the one operational property that must hold
  {{TECH_BASELINE_BULLETS}}   one bullet per stack element, each with a provenance tag: [input] when
                              the constraints fix it, [Q-NNN] for the hosting provider, region and
                              anything paid (external), [D-NNN] for a language, framework or library
                              the inputs leave open (a default with alternatives, never a card)
  {{FILE_TABLE_ROWS}}         one row per spec file, in number order, domain files then
                              traceability, decision-register, implementation-plan, agent-playbook
  {{NN_REGISTER}}             number of the decision register file
  {{ISOLATION_TERM}}          the domain's boundary term ("tenant isolation", "workspace isolation",
                              "per-customer isolation"); if the product has no such boundary, use
                              "data-ownership" and keep the rule
Version/Status lines: leave as written. Stage D changes them to `1.0` / `Implementation baseline`.
The Requirement language, Provenance, Scope labels and Conflict resolution sections are verbatim.
-->
# {{PRODUCT_NAME}} — MVP Specifications

Version: 0.1-draft  
Status: Draft, not yet an implementation baseline  
Audience: Product owner, architects, developers, QA, DevOps and GenAI SWE agents

## Product statement

> {{PRODUCT_STATEMENT}}

{{PRODUCT_PARAGRAPH}}

## Technology baseline

{{TECH_BASELINE_BULLETS}}

## Specification map

| File | Purpose |
| --- | --- |
{{FILE_TABLE_ROWS}}

## Requirement language

`MUST`, `SHOULD` and `MAY` are normative. Unless explicitly labeled Future, every `MUST` requirement is part of MVP acceptance. Every `MUST` is testable: the testing specification or the work package that delivers it names the check that verifies it.

Sections are numbered and never renumbered. New content is appended as a new section or a new bullet; other documents cite `specs/NN-name.md §M` and those citations must keep resolving. `make check-docs` verifies every citation.

## Provenance

Every normative statement ends with a provenance tag:

| Tag | Meaning |
| --- | --- |
| `[input]` | stated by the owner in the raw requirements (`docs/inputs/`) |
| `[Q-NNN]` | decided by the owner by answering question card Q-NNN in `QUESTIONS.md`; `[Q-NNN, recommendation accepted]` when the owner accepted the proposed option |
| `[D-NNN]` | implementation default recorded in `DECISIONS.md` with alternatives; touches no data, security, scope, external or UX decision |
| `[inferred]` | inference not yet ratified; none remain at an implementation baseline |

`{{NN_REGISTER}}-decision-register.md` contains only `[input]` and `[Q-NNN]` statements. `make check-docs` enforces it.

## Scope labels

- **MVP:** required for the first production release.
- **Future:** anticipated in architecture, but not implemented in MVP.
- **Out of Scope:** intentionally excluded; implementation agents must not add it.

## Conflict resolution

1. `{{NN_REGISTER}}-decision-register.md` and the product statement override inferred behavior.
2. Security and {{ISOLATION_TERM}} requirements override convenience.
3. A feature not described as MVP is not silently added.
4. Ambiguities that materially affect data, security or scope become an Architecture Decision Record before implementation.
