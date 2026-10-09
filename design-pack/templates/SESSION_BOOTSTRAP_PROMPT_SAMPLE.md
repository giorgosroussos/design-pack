<!-- TEMPLATE NOTES (delete this block when rendering)
Near-verbatim. Placeholders:
  {{ISOLATION_AXIS}}      "tenant/property" or the domain's boundary; if none, replace the isolation
                          clause in prompt 1 with "authorization cases where a resource is owned by a user or account"
  {{CONTRACT_SENTENCE}}   "Update the OpenAPI contract and regenerate the client whenever a contract changes."
                          or "Update the shared type definitions whenever a contract changes."
  {{NN_REGISTER}} {{NN_PLAYBOOK}} {{NN_PLAN}}
  {{REVIEW_PASS_2}}       the security pass adapted: "attempt cross-tenant, cross-property, wrong-host, expired
                          or regenerated credential, upload and rate-limit abuse" or the domain equivalent
  {{REVIEW_PASS_4}}       the UX pass adapted (languages to test, states)
-->
# Session bootstrap prompts

Copy one of the prompts below into a fresh agent session. Adjust the bracketed parts only when needed. The default prompt works for most implementation sessions because `PLAN.md` already carries the task ID, spec references and acceptance criteria.

## Which of them a task needs

Prompt 1 runs for every task, or prompt 1o in its place when an orchestrator runs several packages at once; prompts 2 and 3 are conditional, and the condition is not a judgement. Before starting the `Now` package, read its `Surfaces`, `Touches red line` and `Contract change` in `specs/{{NN_PLAN}}-implementation-plan.md`, and compute `blocked-by`: the cards in `QUESTIONS.md` under Blocking or Open whose `Blocks:` names the package. `python3 scripts/check-docs.py --task <TASK-ID>` prints all four in one line, and `make brief TASK=<TASK-ID>` opens with the same line before the material the task needs. Then apply the table in `AGENTS.md` "Prompt selection" and run only what it selects, in the order 3, 1, 2. Nothing is written back: the stored three are verified by `make check-docs`, and `blocked-by` is live, so a card resolved this morning changes the answer this afternoon without an edit to the plan.

## 1. Default: implement the current `Now` item

```text
Implement the current `Now` item in PLAN.md using AGENTS.md as the working contract.

Before changing anything, run `make brief TASK=<the Now item's package ID>` and read what it
prints: it selects, from this pack, everything this package cites — its characteristics, the
`Now` item, its block in the plan, the cards blocking it, the text of the spec sections it cites,
the decisions those cite, the layer notes of the packages it names, its TRACEABILITY.md row and
the GAPS.md rows naming it. Then read AGENTS.md, specs/README.md and
specs/{{NN_REGISTER}}-decision-register.md. Read no other document whole unless AGENTS.md's
reading order gives you the reason to. Then inspect the existing code and tests — that is where
this session's reading budget belongs. Restate your assumptions and flag any conflict with a
locked decision before you start.

Work in the smallest vertical slice that produces the item's observable outcome. Add or update
tests in the same change, including {{ISOLATION_AXIS}} isolation cases where a resource is owned.
{{CONTRACT_SENTENCE}}

Record as you go, in the smallest relevant document:
- judgement calls and tooling choices as a `decision-added` event (`scripts/log-append.py`,
  dated, with alternatives) followed by `make rebuild-decisions`; never by editing DECISIONS.md;
- deliberate incompleteness in GAPS.md, never hidden behind a stub;
- anything the specs cannot answer in QUESTIONS.md as a decision card, with spec reference,
  options and their consequences;
- verification evidence (commands run, test names) in TRACEABILITY.md;
- what this package established, what a later slice must not do, and this session's dated
  handoff in docs/layers/<PACKAGE>.md, with its line in the AGENTS.md "Layer notes" index;
- a gate that failed for an environmental reason in docs/gotchas.md, with the measurement,
  rather than retried until it passed.

Spec text may be amended only where AGENTS.md allows it and only with a `spec-amendment`
event appended to the log, and DECISIONS.md rebuilt, in the same change. Never touch a locked decision or a red line without
an approved ADR. Never invent requirements, weaken tests, or mark work done from file presence.

Continue until every acceptance condition of the `Now` item is demonstrably satisfied,
`make verify` passes from a documented starting state, `make check-docs` passes, PLAN.md
accurately describes the remaining work with the completed item removed, and no blocker is
concealed — **or until this session's budget is reached**, whichever comes first. If it is the
budget: stop at a boundary you choose rather than at the one the context runs out at. Do not
begin a sub-task you cannot finish and record. Leave PLAN.md, GAPS.md and TRACEABILITY.md
truthful about what actually runs and passes, write the layer note with its handoff, and name
the next step precisely enough that the next session starts from `make brief` and this note
rather than from a reconstruction.

If a specification ambiguity touches data, security, scope, external commitments or UX, it is
the owner's to decide and never this session's: open it as a card in QUESTIONS.md (the silent
section, the options and their consequences, your recommendation) and stop. Do not continue on
an assumption. An ambiguity that touches none of those is an implementation judgement: record
it as a `decision-added` event with its alternatives, and continue.

Finish by writing the handoff into the `## Handoff` section of docs/layers/<PACKAGE>.md, dated:
behaviour changed, commands run and their results, migration and rollback notes, security and
privacy considerations, follow-ups not implemented. Summarise it here in two or three lines.
The file is what the next session reads; this message is not.
Do not commit unless asked. Commit messages carry no AI attribution.
```

## 1o. Implement one package under an orchestrator

Prompt 1, for a session that is one of several building packages at once in separate
worktrees. It differs from prompt 1 in four ways and no others. It works on the package and the
branch the orchestrator names, inside the package's `File surface:` only. It stages events and
document updates instead of writing them, because several sessions appending to one log fork
its chain and take the same IDs (`.log/README.md` §Staged events). It stops on a surface
question rather than deciding it. And it commits on its branch when the orchestrator's brief
says so. The orchestrator lands the staged work with `make land` once the branch integrates.

```text
Implement work package [PACKAGE] on branch [BRANCH], as the orchestrator's brief names them,
using AGENTS.md as the working contract. You are one of several sessions building packages at
once: the record every package shares is written when each package lands, not by you.

Before changing anything, run `make brief TASK=[PACKAGE]` and read what it prints. Then read
AGENTS.md, specs/README.md and specs/{{NN_REGISTER}}-decision-register.md, and the source tree
inside the package's `File surface:`. Change nothing outside that file surface. If the work
needs a file outside it, stop and report which file and why: another package may own it.

Work in the smallest vertical slice that produces the package's observable outcome. Add or
update tests in the same change, including {{ISOLATION_AXIS}} isolation cases where a resource
is owned. {{CONTRACT_SENTENCE}}

Stage what you would otherwise record; `.log/README.md` §Staged events gives every form. You
never run scripts/log-append.py, `make rebuild-decisions`, `make rebuild-questions` or
`make land`, and you never edit .log/events.jsonl, DECISIONS.md, QUESTIONS.md,
TRACEABILITY.md, GAPS.md, PLAN.md or AGENTS.md. Instead:
- each event you would have appended is one line of .log/pending/[PACKAGE].jsonl, and a record
  you add is named by a placeholder (D-NEW-1, Q-NEW-1, ...);
- each spec amendment is one line of .log/pending/[PACKAGE].amendments, citing the
  `spec-amendment` decision you stage beside it;
- the package's status and evidence, the gap rows to add, narrow or retire, and the plan item
  to remove are lines of the `## Landing` section of docs/layers/[PACKAGE].md;
- what this package established, what a later slice must not do, and this session's dated
  handoff go in the same note, under its three headings;
- a gate that failed for an environmental reason goes in the handoff, with the measurement,
  rather than being retried until it passed.
A placeholder appears only in those two files and that note. Code comments and commit messages
cite a decision by its real ID, in a commit after the package lands.

If a specification ambiguity touches data, security, scope, external commitments or UX, it is
the owner's to decide and never this session's: stop, and report the card you would open (the
silent section, the options and their consequences, your recommendation). Do not continue on
an assumption. An ambiguity that touches none of those is an implementation judgement: stage it
as a `decision-added` with its alternatives, and continue. Never touch a locked decision or a
red line without an approved ADR. Never invent requirements, weaken tests, or mark work done
from file presence.

Continue until every acceptance condition of the package is demonstrably satisfied on your
branch and `make check-docs` passes there (its `pending` rule holds your staging) — or until
this session's budget is reached, in which case stop at a boundary you choose and leave the
staging and the note truthful about what actually runs and passes. Commit on [BRANCH] only if
the orchestrator's brief says so; commit messages carry no AI attribution. Report to the
orchestrator in three lines: what is staged, the card you stopped on if any, and anything
outside the file surface the package turned out to need.
```

## 2. Review pass on a finished slice

Run this in a **fresh session**, never in the one that implemented the slice. The session that
wrote the code holds every assumption the review exists to catch, and it holds them as context
rather than as claims it can see. This is the same reason the design phase gives a specification
to a reader with no memory of the conversation that produced it.

```text
Run a bounded review of the last completed slice ([TASK-ID]) as described in AGENTS.md and
specs/{{NN_PLAYBOOK}}-agent-playbook.md §7. Do not redesign or refactor unrelated code.

Read `make brief TASK=[TASK-ID]`, the slice's layer note and its diff. Then
review in four separate passes and report findings with file evidence and severity:
1. correctness against the spec sections and state invariants;
2. security and isolation: {{REVIEW_PASS_2}};
3. tests: missing negative, concurrency and idempotency cases;
4. UX and accessibility for any UI touched: {{REVIEW_PASS_4}}.

Critical and high findings block merge. Propose fixes but implement only those I approve, or
those that are clearly local and covered by the existing tests. Update GAPS.md for anything
you find that is deliberately deferred.
```

## 3. Resolve open questions before a phase

```text
Prepare the cards in QUESTIONS.md whose `Blocks:` field names [PHASE or TASK-ID].

For each card, read the cited spec sections and the input it names, then confirm or revise
the options and the recommendation with spec impact (none, spec-amendment or ADR) and
implementation cost. Do not implement anything. Present the cards to me in one batch; I will
answer per card or accept the recommendations. After I decide, record each answer on its card,
record the decision as an event and rebuild (type spec-amendment when spec text changes, adr when a
locked decision changes), move the card to Resolved with the decision ID, update the affected
spec text with its provenance tag, and update PLAN.md if the decision changes the next slice.
Run make check-docs before finishing.
```

## Notes

- Keep prompts short. The living documents carry the detail; the prompt only points at them.
- When a session ends early, ask the agent to leave `PLAN.md`, `GAPS.md` and `TRACEABILITY.md` truthful before stopping, and to write what it learned into the package's layer note, so the next prompt 1 picks up cleanly instead of rediscovering it.
- The layer notes are what keep `AGENTS.md` small enough to be read at the start of every session. A session that writes what it established into `AGENTS.md` instead of into its note is trading every future session's reading budget for its own convenience; `make check-docs` refuses it (`layer-notes`).
- Under an orchestrator, prompt 1o replaces prompt 1 and prompts 2 and 3 are unchanged. The orchestrator fills `[PACKAGE]` and `[BRANCH]`, chooses which packages run beside each other from their lanes, file surfaces and `Depends on:`, and lands each one with `make land TASK=<PACKAGE>` after it integrates, one at a time.
- Replace `[TASK-ID]` with the package ID from `specs/{{NN_PLAN}}-implementation-plan.md` (for example FND-01).
- Running every prompt on every task is not the safe default: it spends a session on passes whose dimension the package does not have. The table is the policy, and it lives in `AGENTS.md` so it can be tuned without unlocking the specs.
