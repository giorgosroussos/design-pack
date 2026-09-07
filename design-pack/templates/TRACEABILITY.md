<!-- TEMPLATE NOTES (delete this block when rendering)
Truthful-empty: every package `not started`, evidence `—`. One row per work package in the
plan, in plan order; one row per critical journey in the testing spec.
Placeholders: {{NN_PLAN}} {{NN_TESTING}} {{NN_TRACE}} {{JOURNEYS_SECTION_REF}} (e.g. "§4")
              {{PACKAGE_ROWS}}  | ID | Phase | Outcome (one line) | Key specs | not started | — |
              {{JOURNEY_ROWS}}  | n | Journey | not started | — |
              {{PHASE_EXIT_RANGE}} the plan's phase section range, e.g. "§3–11"
-->
# TRACEABILITY

Implementation status and evidence per work package (`specs/{{NN_PLAN}}-implementation-plan.md`) and per critical journey (`specs/{{NN_TESTING}}-testing-acceptance.md` {{JOURNEYS_SECTION_REF}}). Status values: `not started`, `in progress`, `done`. Status is set only from evidence that ran and passed; never from plans, file presence or stubs. `make check-docs` verifies that every package has exactly one row and that `done` rows carry evidence. The product-intent scope matrix is `specs/{{NN_TRACE}}-traceability.md`.

## Work packages

| Package | Phase | Outcome | Key specs | Status | Evidence |
| --- | --- | --- | --- | --- | --- |
{{PACKAGE_ROWS}}

## Critical end-to-end journeys (`{{NN_TESTING}}` {{JOURNEYS_SECTION_REF}})

| # | Journey | Status | Evidence |
| --- | --- | --- | --- |
{{JOURNEY_ROWS}}

## Phase exit criteria

Phase exit criteria are in `specs/{{NN_PLAN}}-implementation-plan.md` {{PHASE_EXIT_RANGE}}. A phase is exited only when every package in it is `done` here and its exit criteria have recorded evidence. No phase has been entered.

## Reproducing the evidence

From a clone, once FND-01 has delivered the command contract:

```bash
make setup        # dependencies from lockfiles, env examples
make infra-up     # local infrastructure (required by make test and make smoke)
make migrate
make verify       # lint, format-check, typecheck, contract drift check, test, build, check-docs
make smoke
make audit        # the CI dependency-scan gate
make scan-secrets # the CI secret-scan gate
make check-docs   # runs today, before any code exists
```

`make clean-start` runs the same sequence from a fresh environment and tears it down afterwards. Evidence recorded in this file names the command, the date and what it proved; a reviewer must be able to repeat it from this section.
