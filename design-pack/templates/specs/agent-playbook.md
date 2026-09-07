<!-- TEMPLATE NOTES (delete this block when rendering)
Near-verbatim template. Change only the placeholders and the two conditional blocks.
  {{ISOLATION_AXIS}}        the boundary tests must cross ("tenant/property"); if none, render the
                            isolation bullets as "data-ownership" checks and keep them
  {{EXCLUDED_CAPABILITIES}} the register's excluded list, comma-separated ("AI, PMS, payment, Kubernetes")
  {{CONTRACT_ARTIFACTS}}    "OpenAPI and the generated client" or the equivalent; if there is no generated
                            contract, render as "shared type definitions"
  {{NN_REGISTER}} {{NN_PLAN}}
  {{EXAMPLE_PROMPT}}        regenerate §11 from a real Phase 1 or Phase 2 package of the plan, same shape as the block shown
  {{OWNER_CHECKPOINTS}}     the phases after which the owner reviews (from the plan: first user-visible composition,
                            first end-to-end journey, the core operational loop, before launch)
-->
# GenAI SWE Agent Playbook

## 1. Purpose

This playbook turns the specs into bounded coding tasks while controlling hallucinated scope, inconsistent abstractions and unsafe migrations. The operating rules that can be checked mechanically are not repeated here; `make check-docs` enforces them.

## 2. Required task packet

Every agent receives:

- one task ID and one concrete outcome;
- exact relevant spec files and sections;
- repository conventions and current architecture notes;
- dependencies already merged;
- files or modules it may change and the known shared-file owner;
- executable acceptance criteria;
- explicit non-goals;
- commands for lint, tests and build (always `make` targets).

Do not give every agent the whole project unless the task is architectural review. Retrieve only the relevant specs plus `specs/README.md` and `{{NN_REGISTER}}-decision-register.md`. From `DECISIONS.md`, read the index and the entries the current `PLAN.md` item cites.

## 3. Agent execution contract

The agent MUST:

1. inspect current code and tests before editing;
2. restate assumptions and flag conflicts with locked decisions;
3. implement the smallest coherent slice;
4. add or update tests in the same change;
5. run targeted tests, then the relevant broader suite;
6. update {{CONTRACT_ARTIFACTS}} and docs when contracts change;
7. report changed behavior, migration and rollback implications and remaining risks.

The agent MUST NOT:

- change product scope or locked decisions;
- introduce {{EXCLUDED_CAPABILITIES}} or any other excluded capability;
- trust client-supplied {{ISOLATION_AXIS}} identifiers;
- weaken a test merely to make CI pass;
- edit unrelated user code or reformat the repository broadly;
- create speculative abstractions without an MVP consumer;
- commit secrets, sample personal data or raw access tokens;
- perform destructive migrations without an approved migration plan.

## 4. Standard task template

```markdown
# TASK <ID>: <Outcome>

## Context
- Specs: `<file>` §<section>
- Dependencies: <merged tasks>
- Locked decisions: <relevant bullets of the register>
- Decisions to read: <D-NNN entries this task relies on>

## Deliverable
<One observable result>

## Allowed scope
- <modules/files or bounded area>

## Acceptance criteria
- [ ] <executable behavior/test>
- [ ] {{ISOLATION_AXIS}} isolation cases added
- [ ] Authorization and validation enforced server-side
- [ ] {{CONTRACT_ARTIFACTS}} updated if applicable
- [ ] Targeted and regression commands pass

## Explicit non-goals
- <features not to implement>

## Handoff
- Behavior changed
- Tests/commands run
- Migrations and rollback notes
- Security/privacy considerations
- Follow-up items, without implementing them
```

## 5. Definition of Ready

A task is ready only when dependencies are merged, domain and contract behavior is unambiguous, acceptance can be tested, fixtures and roles are identified, and no unresolved card in `QUESTIONS.md` with a `Blocks:` field naming this task or its phase is still open.

## 6. Definition of Done

- Acceptance criteria and the relevant spec behavior implemented.
- Tests include happy path, validation, authorization, {{ISOLATION_AXIS}} isolation and the important state or concurrency failure.
- Static analysis, lint and build pass.
- Migration works on existing data and rollback or forward recovery is documented.
- {{CONTRACT_ARTIFACTS}} synchronized.
- Audit, logging and redaction considered.
- Accessibility and localization states covered for UI.
- No unrelated diff and no hidden TODO replacing required work.
- A human reviewer can reproduce verification from the handoff.
- Files, schemas, routes, components, migrations, mocks or stubs merely existing is never completion; a non-functional stub is a gap and belongs in `GAPS.md`.

## 7. Review agents

Use review as separate bounded passes after implementation:

1. **Correctness reviewer:** checks spec acceptance and state invariants.
2. **Security/isolation reviewer:** attempts cross-{{ISOLATION_AXIS}}, credential and upload abuse.
3. **Test reviewer:** finds missing negative, concurrency and idempotency cases.
4. **UX/accessibility reviewer:** reviews relevant UI only.

Reviewers propose findings with file evidence and severity; they do not redesign unrelated code. Critical and high findings block merge.

## 8. Database-change rules

- One owner per migration sequence or aggregate during active work.
- Prefer additive nullable columns and tables, backfill, enforce, then later cleanup (expand, migrate, contract).
- Index {{ISOLATION_AXIS}} foreign keys and primary query paths.
- Use database constraints for key invariants where practical.
- Never expose sequential IDs because internal keys exist.
- Test migrations on a realistic anonymized dataset before production.

## 9. Contract-change rules

Contract-first for shared work across components. The owning agent publishes {{CONTRACT_ARTIFACTS}} plus fixtures early; consuming agents use the generated artifacts. Do not hand-write duplicate request or response types.

## 10. Context and handoff discipline

Keep a short task log or merge description with decisions and commands. New agents inspect the merged repository and the task handoff rather than trusting stale prose. If code contradicts specs, stop and escalate; do not silently choose one. Before ending a session, leave `PLAN.md`, `GAPS.md` and `TRACEABILITY.md` truthful about what actually runs and passes.

## 11. Example prompt for an implementation agent

```text
{{EXAMPLE_PROMPT}}
```

## 12. Product-owner checkpoints

Require explicit Product Owner review after {{OWNER_CHECKPOINTS}}. These checkpoints validate product behavior without reopening locked architecture absent a real contradiction. Open cards in `QUESTIONS.md` whose `Blocks:` names the next phase are resolved at the checkpoint that precedes it.
