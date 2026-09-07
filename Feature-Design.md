# Task: add derived task characteristics and a prompt-selection policy to the pack

## Context
The generated pack drives implementation through three session prompts in
`SESSION_BOOTSTRAP_PROMPT_SAMPLE.md`: Prompt 1 (implement the Now item), Prompt 2 (bounded review
of a finished slice), Prompt 3 (resolve blocking questions before a phase). Prompt 1 always runs;
2 and 3 are conditional, but nothing in the pack tells an orchestrator *when* each condition
holds. Today an orchestrator either runs all three every task (wasteful — most reviews and
question-passes find nothing the mechanical gates didn't) or hard-codes the policy outside the
pack (drifts from the specs).

Give each work package machine-readable characteristics derived from what it already implements,
and put a readable policy table in AGENTS.md mapping those characteristics to which prompts to
run. The orchestrator reads the Now package's characteristics plus the table and decides, with no
inference pass, which of the three prompts a task needs.

## Design principle
The pack states DATA (what kind of task this is); the policy states POLICY (when that kind needs
review or a question-pass). Keep them separate, mirroring provenance tagging: the pack never says
"run a review here", it says "this package touches security", and the table says what that
implies. Characteristics are DERIVED, not freshly judged — so they stay correct when a decision
changes, and check-docs can verify them.

## Scope — do ONLY this
Add the characteristics to work packages, one check-docs rule, the AGENTS.md policy table, and a
short preamble in the bootstrap sample. Do NOT touch elicitation, surfaces/cards/provenance
semantics, the enforcement layer, the event log, or the projections. Do not change what the three
prompts themselves say.

## The four characteristics

Three are STORED on each work package in the implementation-plan spec
(`specs/NN-implementation-plan.md`), as line-oriented fields so a script can read them:

- `Surfaces:` — the set of surfaces (data | security | scope | external | ux) the package
  touches. DERIVED: the union of the surfaces of the cards and register entries that the spec
  statements in the package's cited sections resolve to. A `[Q-NNN]` statement contributes its
  card's surface; a register bullet contributes the surface heading it sits under. Empty is
  written as `—`.
- `Touches red line:` — `yes` | `no`. DERIVED: yes iff any red line in AGENTS.md cites a spec
  section this package also cites.
- `Contract change:` — `yes` | `no`. This one is an implementation judgement the plan author
  makes at Stage B (does this package define or modify an interface/API/schema contract),
  recorded like any other `[D-NNN]`-class call. check-docs verifies it is present and boolean; it
  does not recompute its value.

The fourth is LIVE, not stored:

- `blocked-by` — the open cards whose `Blocks:` field equals this package's ID. Computed at run
  time from QUESTIONS.md, never frozen into the plan (so resolving a blocking card needs no
  ceremonial unlock of the hard-locked plan). The card→package link already lives in each card's
  `Blocks:` field; the orchestrator reads it directly.

## The policy table (AGENTS.md)

A readable table the orchestrator interprets. Exactly:

| Prompt | Run when |
| --- | --- |
| 1 — Implement | Always. |
| 3 — Resolve questions | Before the package, iff an open card in QUESTIONS.md has `Blocks:` = this package. |
| 2 — Review | After implementation, iff `Surfaces` includes `security` or `data`, or `Touches red line` is `yes`, or `Contract change` is `yes`. Otherwise skip: the executable acceptance criteria and `make check-docs` already cover correctness, and there is no security, isolation or contract dimension for a review to add. |

State, above the table, that the mechanical gates are the floor for every task and the review
prompt is only for what those gates cannot check.

## check-docs additions (extend, do not rewrite existing rules)
One new rule, `task-policy`:
- every work package carries `Surfaces:`, `Touches red line:` and `Contract change:` with allowed
  values;
- the stored `Surfaces:` equals the value recomputed from the package's cited sections;
- the stored `Touches red line:` equals the value recomputed from red-line citations;
- the AGENTS.md policy table names only the three real prompts and only characteristic names this
  rule defines (so a renamed characteristic or a typo in the table fails the build).
It does not recompute `Contract change` (a judgement) beyond checking it is present and boolean.

## Wiring
- Stage B, when it writes the implementation-plan spec, derives and writes the three stored fields
  on every work package, and sets `Contract change` per package. The derivation reuses the same
  card/register/red-line data the pack already holds — no new source of truth.
- Stage C compiles the policy table into AGENTS.md, and adds a short preamble to
  `SESSION_BOOTSTRAP_PROMPT_SAMPLE.md`: before running a Now package, read its characteristics in
  the implementation-plan spec and the policy table in AGENTS.md, compute `blocked-by` from
  QUESTIONS.md, and run only the prompts the table selects.
- `make check-docs` runs the new `task-policy` rule with the rest.

## Acceptance (executable — `scripts/test-task-policy.sh`)
On a small fixture pack (or a generated one):
1. A package citing a security-surfaced section has `Surfaces:` including `security`; check-docs
   passes.
2. A package citing only non-surface sections has `Surfaces: —`; check-docs passes.
3. Hand-edit a stored `Surfaces:` to a value that disagrees with the cited sections → `task-policy`
   fails, naming the package.
4. A red line cites a section a package cites, but the package's `Touches red line:` says `no` →
   `task-policy` fails.
5. The policy table references a prompt or characteristic name that doesn't exist → `task-policy`
   fails.
6. A package with an open card whose `Blocks:` equals it → the live `blocked-by` computation (a
   small helper the bootstrap preamble describes) returns that card; when the card is resolved, it
   returns empty. No plan edit occurs in either case.
Exit non-zero if any case behaves wrong.

## Notes
- Python 3 stdlib + POSIX sh only, consistent with check-docs.py.
- `Surfaces` and `Touches red line` are derived and verified; `Contract change` is a recorded
  judgement; `blocked-by` is live. Keep those four treatments distinct — collapsing them is where
  this goes wrong.
- The table lives in AGENTS.md (free tier), so the policy can be tuned without unlocking specs;
  the characteristics live in the hard-locked plan, so the data the policy runs on cannot drift.