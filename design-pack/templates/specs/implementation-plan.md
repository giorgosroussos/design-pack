<!-- TEMPLATE NOTES (delete this block when rendering)
Phased implementation plan. Sections 1, 12 and 13 are verbatim (lanes in 12 are parameterized).
Phase 0 is fixed in shape: the command contract is ALWAYS FND-01. FND-03 exists only when the
product has an API; FND-04 only when it has a UI. Drop the block and keep numbering of the
remaining packages contiguous (FND-01, FND-02, FND-03).
Domain phases: one section per phase, in dependency order, each with Goal, Work packages
(stable IDs `AAA-NN`, three-letter prefix per phase, bullets = outcomes, not tasks) and Exit
criteria that a test or a command can demonstrate. Every package gets a TRACEABILITY.md row.
Every package ALSO ends with its six characteristics, one per line. The first three are what the
prompt-selection table in AGENTS.md reads; the last three are what a plan needs in order to be split
at Stage B and scheduled in lanes and in order afterwards:
  - Surfaces:            the surfaces the sections this package cites resolve to, in the order
                         data, security, scope, external, ux; an empty set is written as a dash.
                         DERIVED, never judged: a `[Q-NNN]` statement contributes its card's
                         surface, a register bullet the surface of its heading.
  - Touches red line:    yes | no. DERIVED: yes iff a red line in AGENTS.md cites a section this
                         package cites.
  - Contract change:     yes | no. The plan author's JUDGEMENT at Stage B (does this package
                         define or modify an interface, API or schema contract), recorded like any
                         other implementation call. `check-docs` checks it is there and boolean;
                         it never recomputes it.
  - File surface:        the directories or modules this package may change, comma-separated, as
                         the repository layout spells them (`apps/api/app/Domain/Access, apps/api/tests`).
                         A JUDGEMENT, like Contract change: `check-docs` checks it is there and
                         never recomputes it, because only the plan author knows what the package
                         will touch. It is what the playbook's task packet means by "files it may
                         change", and what tells an orchestrator whether two packages can run at
                         once. A package whose surface spans more than one lane is a package Stage
                         B splits, or explains.
  - Lane:                one of the lanes this plan's Safe parallelization section lists, verbatim.
                         A JUDGEMENT checked against that list: a lane nobody defined is a package
                         nobody can schedule. `--task all` reports packages that share a lane and
                         a path, because two of those are not two lanes.
  - Depends on:          the package IDs of the SAME phase that must be `done` before this one
                         starts, comma-separated, or a dash. Phase order is implied and never
                         repeated: a package of another phase fails `task-policy`. PARTLY DERIVED:
                         a package citing a section that a `Contract change: yes` package of its
                         phase also cites lists that package, and `task-policy` fails a missing
                         pair, naming both and the section. Anything more is the plan author's
                         JUDGEMENT, recorded in the same decision as the lanes; it is checked for
                         existence, phase and cycles. `--task all` prints each phase's order.
Do not write the first two by hand: `python3 scripts/check-docs.py --task all` prints the derived
pair for every package, and the `task-policy` rule fails the build when a stored value and the
pack disagree. The next three are written by the plan author and never recomputed, and the sixth
is the author's apart from the contract pairs the gate derives. There is no seventh field:
`blocked-by` is read from QUESTIONS.md at run time, so a card can be resolved without unlocking
this file.
Placeholders:
  {{FND01_CHARACTERISTICS}} {{FND02_CHARACTERISTICS}} {{FND03_CHARACTERISTICS}} {{FND04_CHARACTERISTICS}}
                           the six lines for each Phase 0 package (FND-03/FND-04 only when their
                           conditional block is kept); FND-02 depends on FND-01, whose targets it
                           runs. Domain packages carry their own six lines inside {{DOMAIN_PHASES}}.
Placeholders:
  {{DEPENDENCY_GRAPH}}     mermaid flowchart of phases
  {{STACK_SCAFFOLD_BULLET}} what FND-01 scaffolds ("Create the API app, the two SPAs, ..."), from the architecture spec
  {{INFRA_SERVICES}}        local infrastructure the contract starts ("PostgreSQL and Redis"), or "none" for a static product
  {{CONTRACT_DRIFT_TARGET}} name of the drift-check target when a generated contract exists (e.g. `openapi`); else remove the bullet
  {{PRIMARY_DB}}            the database CI must test against ("PostgreSQL 16"); else "the production database engine"
  {{NN_TESTING}} {{NN_ARCH}} {{NN_API}}  spec numbers by role (the testing file is always NN-testing-acceptance.md)
  {{DOMAIN_PHASES}}         the generated phase sections, starting at "## 4. Phase 1 — ..."
  {{N_PARALLEL}} {{N_BACKLOG}} section numbers for the last two sections (after the last phase)
  {{LANES}}                 lane list adapted to the architecture (one per independently buildable component plus tests and infra)
  {{RELEASE_PHASE_NUMBER}}  the last phase's number
-->
# Implementation Plan for GenAI SWE Agents

## 1. Delivery strategy

Implement in thin, testable vertical increments. GenAI agents work best with bounded tasks, explicit inputs, a small file surface and executable acceptance criteria. Avoid parallel edits to shared foundations such as migrations, contract root files and global authorization middleware.

Each phase ends with a running integrated system. Work packages are relative units of work, not calendar promises. Every package has a row in `TRACEABILITY.md`; a package is `done` only when its acceptance ran and passed.

## 2. Dependency overview

```mermaid
{{DEPENDENCY_GRAPH}}
```

## 3. Phase 0 — Foundations

Goal: a reproducible repository, one command that runs every gate, CI that runs only those commands, and the shared contracts, before any domain work.

### Work packages

`FND-01` Command contract and repository scaffold

- Make every target of the root `Makefile` real, replacing the failing placeholder bodies the documentation pack ships with: `setup`, `infra-up`, `infra-status`, `infra-down`, `migrate`, `dev`, `test`, `lint`, `format`, `format-check`, `typecheck`, {{CONTRACT_DRIFT_TARGET}}, `build`, `verify`, `smoke`, `audit`, `scan-secrets`, `clean-start`. `check-docs` is already real and stays green.
- {{STACK_SCAFFOLD_BULLET}}
- Local Compose (or equivalent) for {{INFRA_SERVICES}}; environment examples; lockfiles committed.
- `make verify` runs every gate the testing specification requires that exists at this point; `make clean-start` proves a fresh clone boots, verifies and tears down.
{{FND01_CHARACTERISTICS}}

`FND-02` CI baseline

- A pipeline on the project's remote, running on every merge request and every push to the default branch, against {{PRIMARY_DB}} as a service, never a lighter substitute (`{{NN_TESTING}}` §Test layers).
- Every job runs exactly one `Makefile` target, so "CI is green" and "`make verify` is green" are the same statement; `README.md` maps job to command.
- `make check-docs` runs as its own job.
- Every gate the testing specification requires but nothing implements yet is a failing-forward tripwire: a job that passes only while the gate is provably absent and fails with promotion instructions the moment it becomes runnable. A missing gate and a silently passing gate must never look alike.
- Dependency and secret scanning; artifact and cache strategy; no job retries.
{{FND02_CHARACTERISTICS}}

<!-- if:API -->
`FND-03` API and observability conventions

- Versioned base path, standard error envelope with a correlation ID, structured logging, health endpoints (`{{NN_API}}`).
- Generated contract and generated client; the drift check target fails when a route changes without regeneration.
- Error-monitoring seam with a local or staging test path.
{{FND03_CHARACTERISTICS}}
<!-- /if -->

<!-- if:UI -->
`FND-04` Design, accessibility and localization foundation

- Shared tokens and base components, focus and error patterns, responsive shell.
- Localization skeleton with the fallback rule the UX spec states; no hard-coded UI strings.
- Automated accessibility smoke test wired as a real gate, replacing its tripwire.
{{FND04_CHARACTERISTICS}}
<!-- /if -->

### Exit criteria

A fresh clone boots locally through `make clean-start`; CI is green on the remote and a red pipeline blocks a merge; `make check-docs` passes; every tripwire is either promoted or still provably absent.<!-- if:API --> Both clients call the health endpoint through the generated client and a controlled error carries a correlation ID.<!-- /if -->

{{DOMAIN_PHASES}}

## {{N_PARALLEL}}. Safe parallelization

After a phase's shared model and contracts are merged, agents may work concurrently on low-overlap packages. Never parallelize migrations for the same aggregate, or concurrent edits to central policies or the contract root, without explicit ownership.

Every work package names one of the lanes below, the file surface it may change and the packages of its phase it depends on, so this section is schedulable rather than advisory: two packages in different lanes whose dependencies are `done` run beside each other, and `python3 scripts/check-docs.py --task all` prints each phase's dependency order and reports any pair that shares a lane and a path. [input]

Suggested maximum lanes:

{{LANES}}

Each lane uses a branch or worktree and integrates through small reviewed merges.

## {{N_BACKLOG}}. Backlog discipline

Each ticket MUST include spec references, dependency and allowed file surface, contract and schema impact, acceptance tests and explicit exclusions. [input]

If a ticket reveals a locked-decision conflict, stop and create an ADR; do not improvise a redesign.
