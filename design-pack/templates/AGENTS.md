<!-- TEMPLATE NOTES (delete this block when rendering)
AGENTS.md is COMPILED from the spec pack in Stage C. It never says anything the specs do not say.
Named, not numbered, because this file has gained sections and will gain more: Authority (the
regime paragraphs), Working method, Prompt selection, Layer notes and Living documents are
near-verbatim; Product, Non-negotiable constraints, Architecture, Commands and Design direction
are compiled.
Ceiling: 20 KB (`check-docs` fails above it). If compiled content does not fit, the red lines
are compressed further, never dropped; detail moves to docs/. Never to the playbook: `specs/` is
hard-locked from the freeze, so anything put there costs a ceremony to change afterwards.
Placeholders:
  {{PRODUCT_NAME}}
  {{PRODUCT_PARAGRAPH}}        4-8 sentences: what it is, what it is not, the core loop, the actors,
                               with citations (`specs/README.md` product statement, `NN` §M for actors)
  {{MVP_SUCCESS_SENTENCE}}     the success criterion from the scope spec, cited
  {{NN_SCOPE}} {{NN_REGISTER}} {{NN_PLAN}} {{NN_PLAYBOOK}} {{NN_TESTING}} {{NN_ARCH}}
  {{TESTING_RELEASE_SECTION}} {{TESTING_JOURNEYS_SECTION}}  section numbers in the testing spec
  {{PLAN_PARALLEL_SECTION}} {{PLAN_LAST_PHASE_SECTION}}      section numbers in the plan
  The playbook's section numbers (§2–§12) are those of templates/specs/agent-playbook.md; if the
  pack's playbook is numbered differently (adopted pack), read the numbers from the file.
  {{ISOLATION_TERM}}           as in specs/README.md
  {{NON_AUTHORITATIVE_PARAGRAPH}}  present only when docs/inputs/ has non-authoritative material:
                               what it is direction for, what it is not, the cards that hold its
                               conflicts (Q-NNN..Q-MMM), pointer to docs/inputs/README.md. Cites D-003.
                               If none: "**Non-authoritative inputs (D-003).** None were received. Any
                               mockup, competitor reference or prior draft added later gets an authority
                               entry in `docs/inputs/README.md` and a `DECISIONS.md` entry before use."
  {{RED_LINES}}                8-12 bullets. Each: bold title, a compression of spec text, citations in
                               parentheses at the end. Every bullet MUST contain at least one §.
                               Derive from: every register bullet, every MUST in the security spec, the
                               excluded list, the testing-honesty rules, identifier rules, secret rules.
  {{STACK_PARAGRAPH}}          the technology baseline as prose with citations
  {{LAYOUT_BLOCK}}             the repository layout from the architecture spec (text block)
  {{TOPOLOGY_PARAGRAPH}}       hosts, storage, async, environments, cited; end with the sentence on
                               tooling the specs leave open ("chosen in DECISIONS.md")
  {{CONTRACT_DRIFT_TARGET_LINE}}  `make openapi        # ...` line or nothing
  {{INFRA_SERVICES}}
  Prompt selection is VERBATIM apart from {{NN_PLAN}}: it is policy over the
  characteristics the plan stores, and a pack that reworded it would fail `task-policy`, which
  reads the table. It costs about 1 KB against the 20 KB ceiling.
  Layer notes is VERBATIM and starts with the empty-index line below: no package has
  been delivered when this file is compiled. Each delivered package later adds ONE line of about
  90 bytes; forty packages cost ~3.6 KB against the same ceiling, which is the arithmetic that
  makes the index the only thing that can live here and the notes themselves a directory.
  {{DESIGN_DIRECTION_SECTION}} present only when visual inputs exist: "## Design direction from <input>"
                               with the principles to carry and the cards holding the conflicts.
                               It is the last section by design. Otherwise omit it.
-->
# AGENTS.md — {{PRODUCT_NAME}}

This file is the entry point for every human or GenAI agent working in this repository. Read it fully before touching anything.

## Product

{{PRODUCT_PARAGRAPH}}

{{MVP_SUCCESS_SENTENCE}}

## Authority and reading order

`specs/` is the authoritative product and engineering contract; its version and status are on `specs/README.md`. Requirement language is normative: every `MUST` not labelled Future is MVP acceptance (`specs/README.md` §Requirement language), and every normative statement carries a provenance tag (`specs/README.md` §Provenance). Conflict resolution, in order (`specs/README.md` §Conflict resolution):

1. `specs/{{NN_REGISTER}}-decision-register.md` and the product statement override inferred behaviour.
2. Security and {{ISOLATION_TERM}} requirements override convenience.
3. A feature not described as MVP is not silently added.
4. Ambiguities that materially affect data, security or scope become an ADR before implementation.

**Amendment regime (D-002).** Agents MAY amend non-locked spec text when implementation genuinely requires it, but never silently: the same change must carry a dated `DECISIONS.md` entry of type `spec-amendment` (what changed, why, alternatives, affected spec sections), and the amended statement keeps or gains a provenance tag. Sections are never renumbered. The following are **excluded from delegation** and require an ADR entry in `DECISIONS.md` marked `Owner approval: pending` plus explicit owner sign-off before any code: every bullet in `specs/{{NN_REGISTER}}-decision-register.md`, and every red line in the next section. If specs conflict with each other, resolve via a recorded decision when the resolution is clear; otherwise record it in `QUESTIONS.md`. Never choose silently. If code contradicts specs, stop and escalate (`{{NN_PLAYBOOK}}` §10).

{{NON_AUTHORITATIVE_PARAGRAPH}}

**Session reading order:**

1. `AGENTS.md`, then `make brief TASK=<PACKAGE>` for the package you are about to work on. The brief is not a summary of the pack: it is the pack, selected by what the package cites — its characteristics, the `Now` item, its block in the plan, the cards blocking it, the text of every spec section it cites, the decisions those cite, the layer notes of the packages it names, its `TRACEABILITY.md` row and the `GAPS.md` rows naming it. Which parts are relevant is a derivation over citations, not a judgement, which is why a command makes it and not you.
2. `specs/README.md` and `specs/{{NN_REGISTER}}-decision-register.md`: short, and they govern everything the brief contains.
3. `docs/gotchas.md` before running the gates for the first time in a session.
4. The source tree the package touches. This is where the session's reading budget belongs.

Read a document **whole** only for the reasons below; each one is a case where a citation cannot tell you what you need.

- All of `specs/` before changing cross-cutting architecture, {{ISOLATION_TERM}}, authorization, the contract root or shared migrations.
- All of `DECISIONS.md` (its index first) when the change is cross-cutting; otherwise the brief already carries the entries the work cites.
- `QUESTIONS.md` when a card's answer is in doubt; the brief carries the ones that block this package, and `PLAN.md` and `GAPS.md` in full when correcting them.
- `docs/inputs/README.md` when a task cites a raw requirement or a non-authoritative input.

## Non-negotiable constraints

{{RED_LINES}}

## Architecture and stack

{{STACK_PARAGRAPH}}

Target repository layout (`{{NN_ARCH}}` §1):

```text
{{LAYOUT_BLOCK}}
```

{{TOPOLOGY_PARAGRAPH}}

## Commands

Root command contract, implemented by the root `Makefile` (FND-01, D-001) with helpers in `scripts/`. Every target below exists. A target whose work package has not been delivered yet fails with a message naming that package instead of passing, so a missing gate and a passing gate never look alike; `make check-docs` is real from the first commit and asserts that this list and the `Makefile` agree. `make test` and `make smoke` need `make infra-up` first when the product has local infrastructure ({{INFRA_SERVICES}}).

```bash
make setup          # install dependencies from lockfiles, copy env examples
make infra-up       # start local infrastructure and wait for health
make infra-status
make infra-down
make migrate        # apply database migrations locally
make dev            # run every application process for local development
make test           # all automated tests against the real database engine
make lint
make format         # apply formatting
make format-check   # verify formatting without changing files
make typecheck
{{CONTRACT_DRIFT_TARGET_LINE}}
make build          # production builds
make verify         # lint + format-check + typecheck + contract drift + test + build + check-docs
make smoke          # health of the running system through its public entry points
make audit          # dependency advisories
make scan-secrets   # secret scan of everything Git tracks
make check-docs     # mechanical consistency of the documentation layer (scripts/check-docs.py)
make check-locks    # lock manifest check of the staged change (scripts/lock-guard.py)
make verify-chain   # recompute every hash and link in .log/events.jsonl
make rebuild-decisions  # render DECISIONS.md from the event log
make rebuild-questions  # render QUESTIONS.md from the event log
make install-hooks  # point git at .githooks/ (once per clone)
make unlock         # ceremonial unlock of one hard-locked path: PATH=<path> REASON="why"
make brief          # everything a session on one package must read: brief TASK=<PACKAGE>
make clean-start    # fresh isolated environment: setup, infra-up, migrate, verify, smoke, teardown
```

`check-docs`, `check-locks`, `verify-chain`, the two `rebuild-*` targets, `install-hooks` and `unlock` are real from the first commit; the rest arrive with FND-01.

CI (FND-02) runs on every merge request and every push to the default branch. Each job runs exactly one of the targets above, so a gate cannot pass in CI and fail locally; `README.md` maps job to command. Gates the testing specification requires that nothing implements yet run as failing-forward tripwires that pass only while the gate is provably absent (`{{NN_PLAN}}` §3).

## Working method and definition of done

Work in the smallest useful vertical slice, following the task packet of `{{NN_PLAYBOOK}}` §2 and §4: one task ID and outcome, exact spec sections, dependencies merged, allowed file surface and shared-file owner, executable acceptance criteria, explicit non-goals. Before coding, inspect current code and tests, restate assumptions and flag conflicts with locked decisions (`{{NN_PLAYBOOK}}` §3). Implement, add tests in the same change, run targeted then broader suites, regenerate contract artifacts when contracts change, and report changed behaviour, migration and rollback implications and remaining risks.

Definition of Ready and Done are `{{NN_PLAYBOOK}}` §5–6. Review runs as separate bounded passes after implementation, when the table in the next section selects it: correctness, security and isolation, tests, UX and accessibility (`{{NN_PLAYBOOK}}` §7). Critical and high findings block merge. Parallel work follows the lanes in `{{NN_PLAN}}` §{{PLAN_PARALLEL_SECTION}}; never parallelize migrations for the same aggregate or concurrent edits to central policies or the contract root without explicit ownership. Product Owner checkpoints are `{{NN_PLAYBOOK}}` §12. The release gate is `{{NN_TESTING}}` §{{TESTING_RELEASE_SECTION}} together with the last phase's exit criteria in `{{NN_PLAN}}` §{{PLAN_LAST_PHASE_SECTION}}.

## Layer notes

One note per delivered work package, in `docs/layers/`, written by the session that delivers it:
what the package established, what a later slice must not do, and the dated handoff of every
session that touched it. This index carries one line per note and never the content, so the
entry point stays readable while the knowledge grows; a session reads only the notes its
dependencies name, which `make brief` selects for it. `docs/layers/README.md` states the form, and
`make check-docs` (`layer-notes`) fails when a `done` package has no note or no line here.

None yet: no package has been delivered. The first one to reach `done` adds its line.

## Prompt selection

`SESSION_BOOTSTRAP_PROMPT_SAMPLE.md` holds three session prompts, and this table decides which of them a task needs. The mechanical gates are the floor for every task, not a prompt: the package's executable acceptance criteria and `make check-docs` run whatever the table says, and the review prompt exists only for what those gates cannot check. Each work package in `specs/{{NN_PLAN}}-implementation-plan.md` states `Surfaces`, `Touches red line` and `Contract change`; the first two are derived from the sections the package cites and `make check-docs` verifies them, the third is the plan author's judgement. `blocked-by` is not stored anywhere: it is the set of open cards in `QUESTIONS.md` whose `Blocks:` names the package, read when the task starts, so resolving a card needs no change to the plan. `python3 scripts/check-docs.py --task <PACKAGE>` prints all four.

| Prompt | Run when |
| --- | --- |
| 1 — Implement | Always. |
| 3 — Resolve questions | Before the package, iff an open card in QUESTIONS.md has `Blocks:` = this package. |
| 2 — Review | After implementation, iff `Surfaces` includes `security` or `data`, or `Touches red line` is `yes`, or `Contract change` is `yes`. Otherwise skip: the executable acceptance criteria and `make check-docs` already cover correctness, and there is no security, isolation or contract dimension for a review to add. |

## Living documents

All at repository root. When scope changes, update the smallest relevant document. Durable rationale goes to `DECISIONS.md`, incompleteness to `GAPS.md`, unresolved choices to `QUESTIONS.md`; `PLAN.md` never becomes an archive. `make check-docs` fails on the inconsistencies that can be detected mechanically; the rules below are the ones it cannot.

- `PLAN.md`: exactly `Now` and `Next`. Keep 1–3 narrow `Now` items and only the next few slices, each with spec refs and executable acceptance. Not history, design or backlog; remove completed items, Git is the archive. If code and plan disagree, investigate and correct the plan.
- `DECISIONS.md`: a generated projection of the `decisions` stream of `.log/events.jsonl`, which is the source of truth. Never edit it and never hand-write an entry: append an event with `scripts/log-append.py` (`decision-added`, `decision-superseded`, `adr-approval-changed`) and run `make rebuild-decisions`. A record carries decision, why, alternatives, affected specs and type (`implementation`, `spec-amendment`, `adr`); an `adr` carries its owner-approval state, changed by its own event. Retire a record by superseding it, which renders as `Status: superseded by D-MMM`; nothing is ever rewritten or deleted, because the alternatives a decision weighed are the only record of why it reads as it does. `make check-docs` verifies the chain (`chain-intact`) and that this file equals a fresh rebuild (`projection-fresh`), so an edit here fails the gate instead of becoming the record. `.log/README.md` states what the chain does and does not guarantee.
- `GAPS.md`: deliberate incompleteness, missing infrastructure, deferred scope, its consequence and the evidence needed to close it. Never mask a gap with a stub. A closed gap's row is removed and its ID retired.
- `QUESTIONS.md`: a generated projection of the `questions` stream of `.log/events.jsonl`, in the decision-card format the file documents. Never edit it: open, answer, defer, reactivate, resolve and supersede cards by appending events (`scripts/log-append.py`) and running `make rebuild-questions`, so a card moves between Blocking, Open and Resolved because an event says so. Resolve a card by writing its answer into the specs with a `[Q-NNN]` tag, or into a decision after the baseline, and appending `card-resolved`; never by deleting it. An owner who changes their mind gets a new card and a `card-superseded` event: the old card stays Resolved and readable, and the citation moves to its successor, which `check-docs` expects. Before a phase starts, resolve the Open cards whose `Blocks:` names it.
- `TRACEABILITY.md`: work packages from `specs/{{NN_PLAN}}-implementation-plan.md` and the critical journeys from `{{NN_TESTING}}` §{{TESTING_JOURNEYS_SECTION}} mapped to status and concrete evidence (test names, commands). Status is set only from evidence that ran and passed, never from plans, file presence or stubs. The product-intent scope matrix remains the traceability file in `specs/`, owner-maintained.
- `docs/layers/<PACKAGE>.md`: what each delivered package established, what a later slice must not do, and its handoff. Written by the session that delivers the package, appended to by any session that changes the layer, indexed in the section above. Never a second copy of the specification: `specs/` says what the product must do, a note says what the code now does about it.
- `docs/gotchas.md`: what the tooling does that an agent cannot predict — a gate that is known to be flaky and the evidence for it, a tool whose output is unreadable under an agent and the flag that fixes it, an environment trap. A gate that fails for an environmental reason is recorded here, never retried into green.
- `.doc-locks`: which files are hard-locked, append-only or free, one `tier: glob` per line, last match wins. `scripts/lock-guard.py` enforces it over the diff from `.githooks/pre-commit` and from the pre-receive hook on the remote; `.githooks/README.md` says why both exist. Run `make install-hooks` once per clone. A hard-locked file changes only through `make unlock PATH=<path> REASON="..."`, which records the reason in `UNLOCKS.md` and authorizes exactly that path for exactly one commit. Tiers only ever go up: promoting a file is a line appended to `.doc-locks` through the same ceremony (the manifest is hard-locked), and the guard refuses any change that would lower a path's tier.
- `AGENTS.md` itself stays under 20 KB, and `make check-docs` (`agents-size`) enforces it. When it does not fit: knowledge about one package moves to that package's layer note, knowledge about the tooling to `docs/gotchas.md`, and anything else to `docs/`. Never into `CLAUDE.md`, and never into the playbook — `specs/` is hard-locked from the freeze, so an addition there costs a ceremony per slice. This file never grows a section of its own per package; the index above is the only thing it carries about them, and `layer-notes` fails on a heading here that names a package.

{{DESIGN_DIRECTION_SECTION}}
