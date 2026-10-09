<!-- TEMPLATE NOTES (delete this block when rendering)
Truthful-empty: Now = FND-01 (always the command contract), Next = the rest of Phase 0.
Under 100 lines. Every acceptance bullet is a command or an observable test outcome.
Placeholders: {{NN_PLAN}} {{NN_ARCH}} {{NN_TESTING}} {{STACK_SCAFFOLD_BULLET}} {{INFRA_SERVICES}}
              {{FND01_LANE}} FND-01's `Lane:` from the plan, verbatim (`check-docs` compares them)
              {{NEXT_ITEMS}} numbered list: FND-02, FND-03 (if API), FND-04 (if UI), one line each
              with outcome and citations
-->
# PLAN

Only `Now` and `Next`. Completed items are removed; Git is the archive. See `AGENTS.md` for rules. Each `Now` item carries its `Lane:` from the plan and a `Branch:`, which an orchestrator writes when it dispatches the item and which is `—` in single-session work.

## Now

### FND-01 — Command contract and repository scaffold

- **Outcome:** every target in the root `Makefile` is real, a fresh clone boots and verifies with one command, and the repository layout of the architecture spec exists.
- **Specs:** `{{NN_PLAN}}` §3 FND-01, `{{NN_ARCH}}` §1 (layout), `{{NN_TESTING}}` §1–2 (test layers and gates the contract must expose).
- **Dependencies:** none. This is the first package.
- **Lane:** {{FND01_LANE}}
- **Branch:** —
- **Scope:** {{STACK_SCAFFOLD_BULLET}} Local infrastructure for {{INFRA_SERVICES}} behind `make infra-up`. Replace every failing placeholder body in the `Makefile` with the real command; keep `make check-docs` as it is. Record tooling choices (test runner, formatter, static analysis, generators) as `decision-added` events with alternatives, then `make rebuild-decisions`.
- **Non-goals:** CI (FND-02); any domain code; any endpoint beyond what `make smoke` needs to prove the processes start.
- **Acceptance (executable):**
  - `make help` lists every target of `AGENTS.md` "Commands" and none exits with the "not implemented" message.
  - `make setup && make infra-up && make migrate && make verify` exit 0 from a fresh clone; `make verify` runs lint, format-check, typecheck, the contract drift check where one exists, test, build and check-docs.
  - `make test` runs against the real database engine named in `{{NN_TESTING}}` §1, never a lighter substitute; a test proves which database is in use.
  - `make smoke` exit 0 against the processes `make dev` starts.
  - `make clean-start` exit 0 from removed volumes to teardown.
  - `make check-docs` exit 0; `TRACEABILITY.md` FND-01 row set to `done` with the commands and their results as evidence; G-001 narrowed accordingly.

## Next

{{NEXT_ITEMS}}
