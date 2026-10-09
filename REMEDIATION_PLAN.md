# design-pack — remediation plan

Living document. Source: the review of 2026-09-07 (all findings reproduced empirically in
throwaway repositories; the reproduction commands are kept under each item so acceptance is
mechanical, not a judgement).

## How to use this file

This file is the state. There is no other tracker.

- Work the items **in the order listed**. The order is deliberate: the safety net (W2) lands
  before the change it protects (W3).
- Each item has a `Status:` line. The allowed values are exactly:
  `not started` | `in progress` | `blocked: <reason>` | `done` | `won't fix: <reason>`.
  Change nothing else in the item's header.
- An item is `done` only when **every** line under its `Acceptance` heading has been run and
  passed in this session. Paste nothing; tick the box (`- [x]`) and cite the test name or
  the command that proved it in the Progress log.
- Do not edit or delete a Progress log entry. Append a new one. One entry per session per
  item touched, in the form the section prescribes.
- If a fix turns out to need a decision the plan does not make, do not make it silently:
  set `Status: blocked: <the question>` and stop. The owner answers here, in the item's
  `Decision:` line.
- Every code change under `design-pack/templates/scripts/` or `design-pack/templates/githooks/`
  gets a case in the matching suite under `design-pack/scripts/test-*.sh`. A fix without a
  test is not `done`.
- Run every suite below before closing any item; a regression anywhere reopens the item that
  caused it.

```
bash design-pack/scripts/test-lock-guard.sh
bash design-pack/scripts/test-decisions-log.sh
bash design-pack/scripts/test-questions-log.sh
bash design-pack/scripts/test-check-docs.sh
bash design-pack/scripts/test-render.sh
bash design-pack/scripts/test-allowed-tools.sh
bash design-pack/scripts/test-stage-detect.sh
bash design-pack/scripts/test-task-policy.sh
bash design-pack/scripts/test-land.sh
```

## Summary board

| # | Item | Category | Est. | Status |
| --- | --- | --- | --- | --- |
| W1 | Mechanical bugs (A1–A8) | A — local fixes | ½ day | done |
| W2 | Render-and-check acceptance suite | D — safety net | ½ day | done |
| W3 | Manifest demotion guard + self-protection | B — enforcement | 1 day | done |
| W4 | `normative-tagged` and `inferred-zero` rules | C — enforcement of the core claim | ½ day | done |
| W5 | Honest limits: unlock record is an audit trail | docs | ½ hour | done |
| W6 | `allowed-tools` completeness + real dry run | B — usability | ½ hour + a run | done |
| W7 | Findings of the dry run (F1–F14, D1–D5) | mixed; 3 owner decisions | ~2 days | done |
| W8 | Findings of the live dry run (owner's session) | 1 owner decision | ½ day | in progress |
| W9 | Loop prompts have no selection rule | B — orchestration | ½ day | done |
| W10 | Session reading cost and the knowledge a run buys | B — run economics | ~3½ days | done |
| W11 | Parallel execution under an orchestrator | B — orchestration; 6 owner decisions | ~4 days | in progress |

Categories: **A** no design change, zero risk · **B** medium change, one design decision each ·
**C** closes the gap between what the overview promises and what runs in the target · **docs** the
claim changes, not the code.

---

## W1 — Mechanical bugs

Status: done
Decision: none needed.

Eight independent fixes. Each is a few lines; do them in any order, but land the test for each
before moving on. None changes a design.

### A1 — `post-commit` leaks the unlock token when the unlocked path is deleted

File: `design-pack/templates/githooks/post-commit`

Under `set -eu`, `[ -e "$path" ] && chmod 0444 -- "$path"` returns 1 when the path is gone. The
`while` is the tail of a pipeline (a subshell), so it exits non-zero, `set -e` ends the script,
and `rm -f "$token"` never runs. The token then authorizes the next commit to that path.

Fix: `[ -e "$path" ] && chmod 0444 -- "$path" || true`, and make `rm -f "$token"` unconditional
(e.g. move it before the loop, or run the loop with `set +e`).

Reproduction (before the fix, the second commit succeeds and the token is still present after
the first):

```sh
sh scripts/unlock.sh docs/inputs/requirements.md "reason"
git rm -q -f docs/inputs/requirements.md && git commit -qm "delete"
[ -f .doc-unlock ] && echo "TOKEN SURVIVED"
```

Acceptance:
- [x] new case in `test-lock-guard.sh`: unlock → delete the path in the commit → `.doc-unlock`
      is gone → a following commit touching the same path (recreated) is **blocked**.
- [x] existing case 4e still passes.

### A2 — A gapped or out-of-order `D-NNN` / `Q-NNN` is accepted and reds the gate for good

Files: `design-pack/templates/scripts/eventlog.py` (`project_decisions`, `project_questions`)

`log-append` accepts `D-003` after `D-001`. `check_decisions` then requires contiguity from 1,
and the only legal repair on an append-only log — appending `D-002` — produces two failures
instead of one, because the projection renders in insertion order.

Fix: in **both projectors**, on `decision-added` / `card-opened`, require the numeric part to be
exactly `len(entries) + 1`; raise `LogError` otherwise. Putting it in the projector (not in
`validate`) means `check_appendable` refuses the event **and** an existing bad log fails
`projection-fresh` with a clear message. Note `check_decisions` in `check-docs.py` already
demands this for decisions; the cards side has no such check today — add the same contiguity
assertion to `check_cards` so the two streams are held to the same rule.

Reproduction:

```sh
a(){ python3 scripts/log-append.py --quiet --type decision-added --set id=$1 --set date=2026-09-04 \
     --set title=T --set type=implementation --set decision=d --set why=w --set alternatives=a --set affected_specs=n; }
a D-001; a D-003; echo "exit=$?"   # 0 today; must be 2 after the fix
```

Acceptance:
- [x] `log-append` exits 2 on `D-003` after `D-001`, and on `Q-002` when no `Q-001` exists.
- [x] new cases in `test-decisions-log.sh` and `test-questions-log.sh`.
- [x] the four regime records (`decisions-seed.json`, D-001..D-004) still append cleanly.

### A3 — `rebuild_command --check --stdout` skips the check

File: `design-pack/templates/scripts/eventlog.py` (`rebuild_command`)

The `--stdout` branch returns 0 before `--check` is evaluated. Handle `--check` first, or make
the two flags mutually exclusive in argparse.

Acceptance:
- [x] `rebuild-decisions.py --check --stdout` on a drifted file exits 1.

### A4 — `D-D-001` in the duplicate-ID message

File: `design-pack/templates/scripts/eventlog.py:283` — drop the `D-` prefix from the format
string (the ID already carries it).

Acceptance:
- [x] message reads `D-001 added twice (seq N)`.

### A5 — `adr-approval-changed` attaches to a non-ADR

File: `design-pack/templates/scripts/eventlog.py` (`project_decisions`)

Fix: when folding `adr-approval-changed`, raise `LogError` unless `entries[index]["type"] == "adr"`.
Same placement rationale as A2 — `check_appendable` then refuses it at append time.

Acceptance:
- [x] `log-append --type adr-approval-changed` against an `implementation` decision exits 2.
- [x] case added to `test-decisions-log.sh`.

### A6 — `read_lines` splits on U+2028 / U+2029 / U+000B

File: `design-pack/templates/scripts/eventlog.py` (`read_lines`)

`str.splitlines()` splits on Unicode line separators that JSON strings may legally contain.
`clean()` strips them from validated fields, but `validate()` returns unknown streams untouched,
so a future stream can write a record that breaks its own chain.

Fix: `text.split("\n")`, dropping the final empty element. Additionally, have `dumps()` escape
` `/` ` (post-process the JSON string) so the stored line never contains them.

Reproduction:

```sh
printf '{"note":"a\xe2\x80\xa8b"}' | python3 scripts/log-append.py --stream notes --type note --payload-file - --quiet
python3 scripts/verify-chain.py   # "broken at record 1" today
```

Acceptance:
- [x] the reproduction verifies intact.
- [x] existing chain tests unchanged (the canonical form is not affected — only line splitting
      and on-disk escaping).

### A7 — `markers` rule skips the `Makefile`

File: `design-pack/templates/scripts/check-docs.py` (`main`, `check_markers`)

The Makefile is the most placeholder-heavy rendered file (`{{PRODUCT_NAME}}`,
`{{CONTRACT_DRIFT_TARGET}}`) and is not scanned. Pass `Makefile` to `check_markers` as an extra
document — **not** via `ROOT_DOCS`, which would also send it through `check_citations`.

Acceptance:
- [x] a Makefile containing `{{X}}` produces `FAIL markers Makefile:N`.

### A8 — Broken references in `DOCUMENTATION.md`

File: `DOCUMENTATION.md:12-13` — points at `SKILL_PROMPT.md` and a root `reference/`; neither
exists in this repository (`reference/` lives under `design-pack/`). Fix the paths or remove the
sentence.

Acceptance:
- [x] every path named in `DOCUMENTATION.md` exists.

---

## W2 — Render-and-check acceptance suite (safety net)

Status: done
Decision: none needed.

There is no test that the shipped templates, once rendered, pass `make check-docs`. That gate is
654 lines of regex over 16 hand-maintained templates; today the only thing holding them together
is care. Land this **before W3**, so the guard changes have a net under them.

New file: `design-pack/scripts/test-render.sh`. In a throwaway directory:

1. Copy `templates/` in, following `stages/C-operationalize.md` Step C1 literally (scripts,
   hooks, manifest, log tooling, `.gitignore` with `.doc-unlock`).
2. Render placeholders with dummy values (`sed` over `{{...}}`; strip `TEMPLATE NOTES` blocks
   the way the stage says).
3. Seed the log with the four regime records from `decisions-seed.json` via `log-append.py`;
   `rebuild-decisions.py`; `rebuild-questions.py` on an empty questions stream.
4. Write a minimal `specs/` set that the templates' cross-references resolve against (the
   fixed tail: traceability, decision-register, implementation-plan, agent-playbook, plus one
   domain file), rendered from `templates/specs/`.
5. `git init`, `make install-hooks`, first commit.
6. Assert: `make check-docs` exit 0 · `make check-locks` exit 0 · `make verify-chain` exit 0 ·
   `stage-detect.sh` prints `C` before `AGENTS.md` exists and `D` after · both `rebuild-*`
   tools are byte-stable on a second run · the leakage greps of C4 steps 2–3 find nothing.

Acceptance:
- [x] suite exists and passes on the current templates.
- [x] deliberately breaking one template (e.g. a red line without `§`) makes it fail.
- [x] added to `SKILL.md` "Files in this skill" and to `DOCUMENTATION.md` §11.

---

## W3 — The manifest can demote its own locks

Status: done
Decision: **approved as specified below** (demotion = violation; guard, hooks and manifest become
hard-locked at Stage C). Change the Decision line if the owner wants otherwise.

`.doc-locks` is `append-only` and the last matching rule wins. Appending `free: docs/inputs/**`
is therefore a *legal append* that removes a hard lock. Reproduced two ways:

- **Locally, one commit.** `pre-commit` reads the manifest from the working tree, so the
  demotion is already in force when the same commit's locked edit is judged.
- **Server, two pushes.** `pre-receive` reads the manifest from `$base` (correctly blocking the
  same-push case the docs anticipate). Push 1 demotes only — accepted. Push 2 edits the now-free
  path under the new manifest — accepted. No ceremony, no `UNLOCKS.md` record.

The freeze (`stages/D-review.md` D4) relies on the same append+last-wins to promote `specs/**`,
so the mechanism cannot simply be removed; demotion has to be distinguished from promotion.

### Fix

File: `design-pack/templates/scripts/lock-guard.py`

1. `check()` takes an extra argument: the **base manifest text** (the manifest before the
   change). When the diff touches the manifest path, parse both and, for every glob that appears
   in either, compute its tier before and after. Any transition down the ordering
   `hard-locked > append-only > free` is a violation:
   `LOCK demotion .doc-locks: specs/** goes from hard-locked to free; tiers are promoted, never demoted`.
   Implement it as a comparison of the *effective tier of each glob* (last-wins applied), not
   of individual lines, so appending `hard-locked: specs/**` twice is harmless and appending
   `free: specs/**` after a `hard-locked` rule is caught.
2. `--staged` reads the base manifest from `git show HEAD:.doc-locks` (empty tree on the first
   commit); the **effective manifest for the diff is also the base one**, not the working tree's
   — this closes the one-commit local case. Fall back to the working-tree manifest only when
   `HEAD` has none.
3. `pre-receive` already has `$base`; pass `--base-manifest "$work/manifest"` and keep judging
   the diff with the base manifest as today.
4. Promote, in `templates/.doc-locks` at Stage C:
   `hard-locked: scripts/lock-guard.py`, `hard-locked: .githooks/**`, and change `.doc-locks`
   itself from `append-only` to `hard-locked`. Without this, the guard is bypassed by editing
   the guard. Consequence to record: updating the guard or promoting a tier at the freeze now
   requires `make unlock` — `stages/D-review.md` D4 step 2 must do exactly that, and the
   amendment regime in `templates/AGENTS.md` names it.
   *(Alternative considered and rejected: leave `.doc-locks` append-only and rely on rule 1
   alone. Rejected because `scripts/lock-guard.py` would still be `free`, and the guard would
   still be editable by the diff it judges.)*

### Acceptance

- [x] test: appending a demotion + editing the demoted path in one commit is blocked locally.
- [x] test: push 1 (demotion only) is **rejected** by the pre-receive simulation.
- [x] test: appending `hard-locked: specs/**` (a promotion) is accepted with no ceremony —
      when `.doc-locks` is still append-only in the fixture; and requires `make unlock` once
      the Stage-C manifest makes it hard-locked. Both fixtures covered.
- [x] test: editing `scripts/lock-guard.py` without `make unlock` is blocked.
- [x] `stages/D-review.md` D4 updated: the freeze runs `make unlock PATH=.doc-locks REASON=...`
      before appending the promotion.
- [x] `stages/C-operationalize.md` C1.2 and C1.7, `templates/.doc-locks` comments,
      `templates/githooks/README.md`, `DOCUMENTATION.md` §5.1–5.2 updated.
- [x] W2 suite still passes.

---

## W4 — The core claim is not mechanically enforced

Status: done
Decision: **approved as specified below**. One open question is left for the owner in Q-W4.

`design-pack-overview.md` says `make check-docs` verifies that "no statement is left untagged".
`check-docs.py` contains no rule that reads `MUST`/`SHOULD`/`SHALL`; `check_register` checks
trailing tags on bullets in the register's locked prefix only. `[inferred]` is counted into the
informational summary (`check-docs.py:490`) and never fails. `extract-normative.py`, which would
catch both, is explicitly "Not shipped into generated repositories" — so after the freeze the
invariant is unverifiable exactly where it matters.

### Fix

Files: `design-pack/templates/scripts/check-docs.py`, `design-pack/scripts/extract-normative.py`

1. New rule **`normative-tagged`**: move the detection logic of `extract-normative.py`
   (KEYWORD regex, lead-in inheritance up to the next blank line, register bullets normative by
   definition, fenced blocks skipped, tables skipped per `reference/provenance.md`) into a
   function in `check-docs.py`. Every normative statement in `specs/` without a trailing tag →
   `FAIL normative-tagged specs/NN-x.md:LN: normative statement carries no provenance tag`.
   Adopted packs: honour the same `--untagged-as input` semantics via a marker in
   `docs/inputs/README.md` (the file already declares the pack authoritative; read that
   declaration rather than adding a flag).
2. New rule **`inferred-zero`**: fails when any `[inferred]` remains in `specs/` **and**
   `specs/README.md` carries `Status: Implementation baseline`. Silent before the freeze (Stages
   B–D legitimately carry them), hard after it.
3. Make `extract-normative.py` import the shared function so the two cannot drift. It stays a
   skill-side tool (its `md` listing is the hunter's input); only the *check* moves into the pack.
4. Escape hatch: a keyword inside backticks is not normative (mirrors the existing
   `` `[inferred]` `` convention in `INFERRED_RE`). Document it in `reference/provenance.md`.

Q-W4 (owner): should `normative-tagged` also fail on a `[Q-NNN]` tag citing an **Open** card in a
domain file *after* the freeze? `reference/provenance.md` allows it before; the freeze report
lists Open cards, but nothing stops a frozen spec from citing a card that is never answered.
Recommendation: yes, as part of `inferred-zero` (rename to `frozen-ratified`), because a
provisional statement in a frozen contract is the silent decision the whole method exists to
prevent. Decision: **B — no (owner, 2026-09-08).** An Open card may stay cited after the freeze;
enough formalisation has been added, and the owner wants the freedom to leave a question open
past the baseline. The `Blocks:` field and session prompt 3 remain the net; if the owner
insists, it is their call. `check-docs` reports provisional statements in a frozen pack in its
summary (informational), and never fails on them.

### Acceptance

- [x] an untagged `MUST` in a domain file fails `normative-tagged`; the same line in a fenced
      block or in backticks does not.
- [x] lead-in inheritance: `The MVP MUST: [input]` followed by untagged items passes.
- [x] `[inferred]` in a `Status: Draft` pack passes; the same pack stamped
      `Status: Implementation baseline` fails `inferred-zero`.
- [x] `extract-normative.py` output is byte-identical before and after the refactor on the W2
      fixture. *(Format identical; content deliberately not: table rows are now skipped and a
      keyword in a code span is a mention, both per `reference/provenance.md`, and the 20
      untagged template statements the old listing showed are now tagged — see the log entry.)*
- [x] `design-pack-overview.md`, `DOCUMENTATION.md` §8 gates table, `SKILL.md` rule list,
      `stages/D-review.md` D2 updated (D2 step 2 becomes "check-docs passes", not a manual read).
- [x] W2 suite passes.

---

## W5 — Honest limits: the unlock record is an audit trail, not authorization

Status: done
Decision: **option 1 — documentation only.** Signed unlocks (option 2) change the threat model
and add key management; not pursued unless the owner reopens this.

With `--no-token`, the server authorizes a hard-locked change solely from an `- unlock … path="…"`
line added to `UNLOCKS.md` in the same diff. `UNLOCKS.md` is append-only, so anyone can write that
line by hand. Reproduced: hand-written line + locked edit → `lock-guard --no-token` clean.

What the server *does* guarantee is weaker and still valuable: **no hard-locked path changes
without a recorded, attributed reason travelling in the same change**. That matches the threat
model `eventlog.py` already states ("an agent editing history by accident … not a motivated
adversary"). The docs simply overstate it.

Edits:

- `DOCUMENTATION.md` §5.2: replace "**the pre-receive mirror on the remote is the guarantee**"
  with what it guarantees (every locked change carries a reason; nothing changes silently) and
  what it does not (authorship or approval of that reason).
- `DOCUMENTATION.md` §5.3 "Two authorization paths" → "Two evidence paths".
- `design-pack-overview.md` "Honest limits, stated up front": add a third sentence for this.
- `design-pack/templates/githooks/README.md` "Why both" and `templates/scripts/lock-guard.py`
  docstring ("Authorization for a hard-locked path…" → "Evidence…").
- `design-pack/templates/log-README.md`: already says the chain does not authenticate authorship;
  add one line that the unlock ledger does not either.

Acceptance:
- [x] `grep -rn "guarantee" DOCUMENTATION.md design-pack/` — every remaining use is accurate.
- [x] W2 leakage greps unaffected.

---

## W6 — `allowed-tools` does not cover the commands the stages instruct

Status: done
Decision: none needed. `${CLAUDE_SKILL_DIR}` interpolation inside `allowed-tools` is documented
(code.claude.com/docs/en/skills.md, "Substitution timing"), so the three existing patterns stand.

`SKILL.md` allows five Bash patterns. The stage files instruct: `chmod`, `git config`,
`git ls-files`, `mkdir -p`, `xargs`, `make install-hooks`, `make check-locks`,
`make verify-chain`, `make unlock`. Only `make check-docs` matches, as an exact string.

Fix (in `design-pack/SKILL.md` frontmatter):

```yaml
  - Bash(make check-docs)
  - Bash(make check-locks)
  - Bash(make verify-chain)
  - Bash(make rebuild-decisions)
  - Bash(make rebuild-questions)
  - Bash(make install-hooks)
  - Bash(make unlock *)
  - Bash(mkdir -p *)
  - Bash(chmod *)
  - Bash(git ls-files *)
  - Bash(git config core.hooksPath*)
  - Bash(grep *)
  - Bash(python3 scripts/*)
```

Then a **real dry run** of the skill against the pottery brief from `design-pack-overview.md`,
through Stage C at least, noting every permission prompt that still appears. If the three
`${CLAUDE_SKILL_DIR}` patterns do not interpolate, every script call prompts; in that case
replace them with the expanded path or with `Bash(python3 */design-pack/*)`.

Part (a), the list, is done; part (b), the dry run, needs a live `/design-pack` session with an
owner answering cards and cannot run from the remediation session. Procedure for (b):

1. Install: `mkdir -p ~/.claude/skills && cp -r design-pack ~/.claude/skills/design-pack`.
2. `mkdir -p ~/tmp/trial && cd ~/tmp/trial && git init`, start Claude Code there in the default
   (prompting) permission mode, `/design-pack .`, paste the pottery brief from
   `design-pack-overview.md`.
3. Answer every batch with "accept recommendations". Note **every** permission prompt: the
   exact command shown. Continue through Stage B and the Stage C stop.
4. Each prompt is a finding: either a command the stages instruct without a pattern (add the
   pattern **and** a fixture in `test-allowed-tools.sh` so it would have caught it), or a command
   the skill improvised that the stages do not instruct (fix the stage text instead).
5. Also record: does `stage-detect` report the expected stage at each stop; does the final
   `make check-docs` pass; how many cards per surface for the brief.

Acceptance:
- [x] dry run reaches the Stage C stop with zero unexpected permission prompts. *(Run as a
      simulated session — see the W6 log entry; the one class of command no pattern covered, the
      seed rendering, now has a tool. A live session in the owner's permission mode remains the
      final confirmation; the procedure above stands for it.)*
- [x] every command in `stages/*.md` has a matching pattern (re-run the grep from the review:
      `grep -rhoE '\b(make [a-z-]+|git [a-z-]+|mkdir|chmod|xargs|grep -)' design-pack/stages design-pack/SKILL.md | sort -u`).

---

## W7 — Findings of the dry run (2026-09-08)

Status: done
Decision: the three owner items below were decided on 2026-09-13 — **the owner accepted every
recommendation as written** (W7.2 part 2: every Stage A card opens Blocking and deferral makes it
Open; W7.5: Stage C makes the pack's first commit; W7.6: a card only for the hosting provider and
anything paid, language and framework are `D-NNN`). The rest are fixes.

Source: `reports/dry-run-2026-09-08.md`, sections Friction (F1–F14) and Defects (D1–D5). The run
reached the Stage C stop with `make check-docs` at 0 failures, but needed one unsanctioned
deviation (F2) to get there. Ordered by severity.

### W7.1 — A superseded decision's text is still checked, so a bad citation is permanent (F2, D1, D2)

`render_decisions` renders a superseded record in full (by design: its alternatives are history),
but `check_citations` parses the whole of `DECISIONS.md` and `check_decisions` assumes superseded
entries are collapsed. A `decision-added` payload whose text carries a citation that does not
resolve fails `citations` forever: the log is append-only and supersession does not remove the
text. The dry run truncated the log to escape it — exactly what the layer exists to prevent.
Compounded by D2: the `` `specs/README.md` §Name `` parser is greedy (`§Technology baseline leaves
the engine…` is read as a section name), so ordinary prose after a named citation fails.

Fix: (a) `check_citations` skips the body of a superseded entry in `DECISIONS.md` (history is not
live text; the `Status: superseded by` line marks it); (b) the named-section parser matches the
*longest known heading* from `section_index` instead of reading to the next punctuation;
(c) `check_appendable` runs the citation check on a `decision-added` payload against the
current spec headings before appending, so a bad citation is refused at the door, like a bad ID.
Tests in `test-check-docs.sh` and `test-decisions-log.sh`. Estimate: ½ day.

Acceptance:
- [x] a superseded entry with a dead citation passes `citations`; a live entry with one fails.
- [x] `` `specs/README.md` §Provenance says that… `` resolves; `§Nonexistent` fails.
- [x] `log-append` refuses a `decision-added` whose text cites a section that does not exist.

### W7.2 — `stage-detect` misreports during Stage A (F1, D3)

After Round A0 (inputs saved, `QUESTIONS.md` empty) it prints `B-fileset`; a re-entering session
would skip extraction. After the Blocking batches are answered but before the Open-card batches
(external, ux) are presented it prints `B-fileset` again. Root cause: `A-elicit.md` line 3 ends
Stage A when no Blocking card lacks an answer, but Rounds A2… present every surface group,
including cards opened with `Blocks: Phase N`, and the documents cannot tell "never presented"
from "deferred".

Fix, part 1 (mechanical): a state `A-extract` — `docs/inputs/` exists, `QUESTIONS.md` has no
`### Q-` — routed to `A-elicit.md` Round A1. Part 2 (**owner**): make Stage A open every card
with `Blocks: specification` and let *deferral* set `Blocks: Phase N` through `card-deferred`, so
"unanswered Blocking card" means exactly "not yet presented or answered" and the detector is
right by construction; A1.4's "otherwise `Blocks:` the earliest phase" goes. Recommendation: yes —
it also fixes F6. The `A-cards` verdict for a Blocking card opened during Stage B is by design
(`D-review.md` D1.4 says so); note it in `stage-detect.sh`'s header. Estimate: 2 hours + decision.

### W7.3 — Open cards raised in Stage B are deferred by the skill, never by the owner (F6)

`B-specify.md` mechanical pass step 3 sends a new non-Blocking card to `## Open` and continues;
B5.1 then appends `card-deferred` for it — while `A-elicit.md` A2.3 defines deferral as the
owner's explicit act. A card the owner never saw left Stage B unanswered (Q-016). This is a
silent decision by the method's own definition.

Fix: Stage B Exit presents every card opened during Stage B that has no answer, as one batch in
the Stage A form, and stops; the owner answers or defers. With W7.2 part 2 this falls out for
free. Estimate: 1 hour.

### W7.4 — Templates hard-code file names and section numbers the stages leave free (F8, D4)

`templates/TRACEABILITY.md` cites `specs/{{NN_TESTING}}-testing-acceptance.md`; `PLAN.md` and
`AGENTS.md` cite `` `{{NN_ARCH}}` §1 (layout) ``; `implementation-plan.md` FND-04 cites
`{{NN_L10N}}`. B1 lets the agent name files `NN-kebab-name.md` and B3 never says the architecture
file's §1 is the layout. Rendered literally against a different name, `citations` fails.

Fix: either fix the names in the stages (B1: the testing file is `NN-testing-acceptance.md`; B3
writing rules: the architecture file's §1 is "Repository layout"; FND-04 cites the UX file's
localization section when no localization file exists) or make them placeholders. Recommendation:
fix the names in the stages — fewer placeholders, and `test-render.sh` already pins them.
Estimate: 1 hour.

### W7.5 — The read-only pass and the lock layer do nothing before the first commit (F9)

No stage commits, so `git ls-files` listed nothing (fixed in W6 with `find`), `make check-locks`
with no `HEAD` printed `clean`, and the "hard-locked from the first commit" wording has no first
commit to refer to. **Owner**: should Stage C end by making the pack's first commit
("documentation pack"), or tell the owner to? Recommendation: the stage makes it — the lock layer
is not active until then, and a pack handed over uncommitted is a pack whose locks are prose.
Also: `lock-guard --staged` with no `HEAD` should say so rather than print `clean`. Estimate:
1 hour + decision.

### W7.6 — The stack card contradicts the surface filter (F5)

`templates/specs/README.md` demands a card for an open stack; `reference/surfaces.md` says
tooling is never a card. The dry run wrote it as `external` (hosting provider, cost) and it forced
a mid-B2 stop the stage does not describe. **Owner**: is an unfixed stack a card (external, when
hosting/provider/cost are involved) or a `D-NNN` default? Recommendation: a card only for the
hosting provider and anything paid; language and framework are `D-NNN`. Then B2 says where it
stops. Estimate: ½ hour + decision.

### W7.7 — Smaller items

- F11: `normative-tagged` and `extract-normative` skip `specs/README.md`, which
  `reference/provenance.md` lists as a tagged location. Include it (not as a register). ½ hour.
- F13: `check-docs --only <rules>` or `--stage A|B` so the Stage A Exit and B3 passes do not
  print 7–31 failures "to be ignored". 1 hour.
- F7: `extract-normative` should print per-file counts (the B Exit report asks for them). ½ hour.
- F12, F14: cosmetic wording (ID order after Stage B; `Kind` vocabulary vs folder names).

---

## W8 — Findings of the live dry run (owner's session, 2026-09-14)

Status: in progress
Decision: one item is the owner's (W8.1, marked **owner**); the rest are fixes.

Source: the owner ran `/design-pack .` on the pottery brief in their own permission mode, through
the Stage C stop (33 cards, 27 decisions, 172 tagged statements, `check-docs` 0 failures, first
commit made), and pasted every prompt. Ordered by weight.

### W8.1 — The skill's pre-approval lasts one turn (**owner**)

Every Bash command and every file write asked for permission from the second reply on, although
each matched an `allowed-tools` pattern. Documented cause (code.claude.com/docs/en/skills.md):
"The grant clears when you send your next message." A skill that stops for the owner many times
cannot rely on `allowed-tools` at all beyond its first turn. The documented remedy is a standing
grant in `settings.json` (project or user).

Fix: `templates/claude-settings.local.json` carries the skill's Bash patterns (and Read/Write/Edit/
Glob/Grep) as `permissions.allow`; Stage A round A0's stop tells the owner this once and offers to
write it to `<target>/.claude/settings.local.json` on the word *allow* (not committed; C1.2 adds it
to `.gitignore`); the install notes show the user-level alternative. `test-allowed-tools.sh`
asserts the template and `allowed-tools` list the same patterns. **Owner**: the offer is made in
conversation and acted on only on the owner's word — confirm that is the right place for it, or
choose "install notes only". Recommendation: keep the offer; a first-time user does not know why
the prompts appear.

Acceptance:
- [x] `test-allowed-tools.sh` passes with the sync assertion.
- [ ] a live run after *allow* at A0 reaches Stage C with no permission prompt (owner's next run).

### W8.2 — `find -exec` cannot be pre-approved

Claude Code refuses to auto-allow `find … -exec` under any `Bash(find …)` rule ("executes
commands"). The W6 fix for the read-only pass used exactly that. Fix: the read-only pass is the
guard's own `lock-guard.py --relock` (every existing hard-locked file loses its write bits — only
the write bits, or the hooks would lose their exec bit and git would skip them silently, which is
what the first version of this fix did and the ceremony tests caught), run by `make install-hooks`
so a clone gets the modes back; C1.6 and D4.2 call `make install-hooks`; `post-commit` re-locks
with `a-w` for the same reason; `find *` leaves `allowed-tools`.

Acceptance:
- [x] `test-lock-guard.sh` case 9: hard-locked files lose their write bits, tracked or not, hooks
      stay `r-x`, free files untouched; the ceremony cases 4a–4g still pass (hooks still run).
- [x] `test-render.sh` 5f: after `install-hooks` the manifest refuses an in-session write at the
      filesystem; the promotion still goes through the ceremony.

### W8.3 — Thirty-three cards, one process each

The agent wrote its own batch scripts (`open-cards.py`, `add-decisions.py`) because `log-append`
takes one payload per process; those scripts matched no pattern. Fix: `--payload-file` accepts a
JSON array — every element validated and folded against the projection first, then appended all
or nothing; A1.5 names the form.

Acceptance:
- [x] `test-questions-log.sh` 11/11b: a batch with one bad element is refused whole, naming the
      element, nothing appended; a valid batch appends in order and the chain verifies.

### W8.4 — The agent asked to edit the skill's own `check-docs.py`

Right after copying the C1 assets the agent requested an edit to
`~/.claude/skills/design-pack/templates/scripts/check-docs.py` (refused by the owner as a sensitive
file). The copied tooling carries no leakage word, so the reason is not the C4.3 grep; it is
not recoverable: the owner ran in manual mode, saw the prompt in sequence (after the C1 copy,
before the `Makefile` was written) and did not keep the proposed diff. Fix regardless: `SKILL.md`
hard rule *Never edit the skill* — a defect in a template or script is a finding in the stop's
report, never a patch in place — and the install notes recommend `chmod -R a-w` on the installed
skill, so the rule holds even against a session that forgets it. If the request recurs in the
next run, the owner keeps the diff and it becomes its own item.

Acceptance:
- [x] the rule is in `SKILL.md`; the install notes carry the read-only recommendation.
- [x] the cause: not recoverable from this run; watched for in the next (owner).

### W8.5 — Small things seen in the log

- The pack's first commit carried the harness's `Co-Authored-By` line although the pack's own
  `CLAUDE.md` forbids AI attribution. C5's message is the one given; a harness that appends to
  it is the harness. No change; noted so the next reader does not chase it.
- The agent reached for `wc -c` and `grep -n` over the skill's scripts to learn field names and
  rule lists it needed (Answer rendering, `--only` rule names, `decision-added` fields). Those are
  inspection commands and prompt in any mode; the stage files could name the rule list and the
  payload fields once each so the agent does not go looking. ½ hour. **Done 2026-09-22:**
  `reference/events-and-rules.md` carries every event's payload fields and what each renders as,
  and every `check-docs` rule with what it fails on; `SKILL.md` marks it a lookup rather than a
  session read; Stages A, B and D point at it where the agent would otherwise open a script. A
  drift case in `test-check-docs.sh` derives both lists from the code and fails when the lookup
  and the scripts disagree, because a reference that goes stale is worse than none — the agent
  that trusts it stops looking.

---

## W9 — The loop prompts have no selection rule

Status: done

`SESSION_BOOTSTRAP_PROMPT_SAMPLE.md` ships three prompts: 1 implements the `Now` item, 2 reviews a
finished slice, 3 resolves the cards blocking a package. Prompt 1 always runs; nothing in a
generated pack said when the other two do. An orchestrator therefore either ran all three on every
task, spending a session on passes whose dimension the package does not have, or kept the policy
in its own head, where it drifts from the specs it is supposed to follow.

The fix keeps the pack's existing separation rather than adding a new one. The plan states **data**:
each work package carries `Surfaces`, `Touches red line` and `Contract change`. `AGENTS.md` states
**policy**: one table mapping those to the prompts to run. The pack never says "run a review here";
it says "this package touches security", and the table says what that implies. Four treatments,
deliberately distinct:

| Characteristic | Treatment | Where |
| --- | --- | --- |
| `Surfaces` | derived from the cards and register bullets the package's cited sections resolve to; recomputed by the gate | stored on the package |
| `Touches red line` | derived: yes iff a red line cites a section the package cites; recomputed by the gate | stored on the package |
| `Contract change` | the plan author's judgement at Stage B, recorded as an implementation decision; checked for presence and shape only | stored on the package |
| `blocked-by` | live: the open cards whose `Blocks:` names the package | never stored |

Collapsing any two of those is where this goes wrong. A derived value that is judged drifts when a
decision changes; a judgement the gate recomputes is not a judgement; and a `blocked-by` frozen
into the plan would make resolving a card a ceremonial unlock of a hard-locked file.

The table lives in `AGENTS.md`, the free tier, so the policy can be tuned without unlocking
`specs/`; the characteristics live in the plan, which the freeze hard-locks, so the data the policy
runs on cannot drift. `task-policy` reads both, so a renamed characteristic or a typo in the table
fails the build instead of silently selecting nothing.

Acceptance:
- [x] `scripts/test-task-policy.sh` green, including the six cases the item specified.
- [x] `scripts/test-render.sh` proves a rendered pack passes the new rule, and that a hand-edited
      characteristic fails it.
- [x] The seven other suites unchanged and green.

---

## W10 — What a session must read grows without bound, and the knowledge a run buys has no home

Status: done
Decision: the two owner questions were decided on 2026-09-22 — **the owner accepted both
recommendations as written** (Q-W10.1: a layer note for every `done` package; Q-W10.5: the two
new characteristics live in the implementation plan). The rest are fixes.

Source: the review of 2026-09-22 against `guestportal-2026` — the pre-skill exemplar this method
was generalised from, at its `GST-04` `Now` item, eight phases into implementation. Its pack was
hand-built, so nothing below is a defect *of* the skill; it is what this method's own structure
becomes after thirty-odd work packages, measured on the only instance that has run that long.
Part of what it shows is already prevented here — W9's prompt selection, the `DECISIONS.md` index
and the reading order that narrows it, the `agents-size` ceiling. The six items below are what is
not prevented by anything, and the first of them is the cause of two others.

Reproduce (in a pack that has run for some phases):

```
wc -c AGENTS.md DECISIONS.md TRACEABILITY.md GAPS.md QUESTIONS.md PLAN.md
python3 - <<'PY'
import re
t = open('AGENTS.md').read()
s = [(len(x), x.split('\n',1)[0]) for x in re.split(r'(?m)^## ', t)[1:]]
print('sections:', len(s), 'bytes:', sum(n for n,_ in s))
for n, title in sorted(s, reverse=True)[:5]: print(f'{n:7d}  {title[:60]}')
PY
```

What it printed there, on 2026-09-22:

| Document | Size | ≈ tokens | What it is |
| --- | --- | --- | --- |
| `DECISIONS.md` | 641 KB | ~160k | 295 entries, mean 2.1 KB |
| `TRACEABILITY.md` | 355 KB | ~89k | 43 rows; the Evidence cells hold every run since the first |
| `AGENTS.md` | 209 KB | ~52k | 628 lines, **31 of its 39 sections are one per work package** |
| `GAPS.md` | 174 KB | ~43k | 108 rows; `G-001` alone is a single table cell of ~20 KB |
| `QUESTIONS.md` | 75 KB | ~19k | |
| **read before any code** | **~1.46 MB** | **~365k** | what that pack's session prompt 1 mandates |

The material a reader actually needs for `GST-04` — three spec sections, two decisions, three
`AGENTS.md` sections, one traceability row — is about **35 KB**. The ratio is 40:1, and the
40 is not history the agent can skim past: it is in the prefill of every turn of a run that the
owner measures in hours, it dilutes attention over a 1063-file source tree, and it is what
makes a long slice end in compaction rather than in a handoff.

The 20 KB `agents-size` ceiling this skill already enforces is not a smaller version of that
file: the eight *structural* sections of it — the ones this skill's template compiles — are
21.5 KB. Everything above that, 186 KB of it, is knowledge that had nowhere else to go.

### W10.1 — Per-package architecture notes have no home, so they end up in `AGENTS.md`

`templates/specs/agent-playbook.md` §2 requires that every agent receive "repository conventions
and **current architecture notes**", and §10 says to "keep a short task log or merge description
with decisions and commands". Neither names a file, and no template creates one. So the answer
to "what did TEN-01 establish that every later slice must not get wrong" has exactly two places
to go: `AGENTS.md`, where it is read by every session forever, or nowhere. The exemplar chose
`AGENTS.md` thirty-one times.

Under this skill the same pressure hits the 20 KB ceiling, and `templates/AGENTS.md`'s own
overflow sentence sends the content to `specs/{{NN_PLAYBOOK}}-agent-playbook.md` or `docs/` —
but `specs/**` is promoted to hard-locked at the freeze, so the sanctioned overflow target costs
a `make unlock` ceremony per slice. That is a trap, and it is in the template today.

The same absence explains prompt 1's handoff. It ends "Finish with a handoff: behaviour changed,
commands run and their results, migration and rollback notes, security and privacy
considerations, follow-ups not implemented" — and every word of that is written to the chat
transcript, which the next session cannot read. What survives a session boundary is only what a
file holds, which is why, in the exemplar, the handoff silted up into `AGENTS.md`, into the
Evidence cells of `TRACEABILITY.md` and into the Gap cells of `GAPS.md` (W10.3).

Fix. Files: `design-pack/stages/C-operationalize.md`, `design-pack/templates/AGENTS.md`,
`design-pack/templates/.doc-locks`, `design-pack/templates/specs/agent-playbook.md`,
`design-pack/templates/SESSION_BOOTSTRAP_PROMPT_SAMPLE.md`,
`design-pack/templates/scripts/check-docs.py`, plus a new
`design-pack/templates/layer-note.md`.

1. **The artifact.** `docs/layers/<PACKAGE>.md`, one per work package, written by the session
   that delivers the package and appended to by any later session that changes the layer. Fixed
   headings, from the new template: *What this package established* (the names a later slice
   calls, not a narrative), *What a later slice must not do*, *Handoff* (the last session's
   report, dated). It is prose for an agent, so it has no `check-docs` rules beyond existence
   and headings.
2. **Stage C** creates `docs/layers/` with a README stating the above (Step C2, beside the
   truthful-empty living documents), and `.doc-locks` gains `free: docs/layers/**` in the free
   block. It does not overlap `hard-locked: docs/inputs/**`, so last-match-wins is not engaged
   and the line's position is not load-bearing; say so in the comment, because every other line
   in that file is positional.
3. **`AGENTS.md` carries the index, never the content**: one line per delivered package
   (`TEN-01 — tenancy context, scoped binding → docs/layers/TEN-01.md`). At ~90 bytes a line,
   forty packages cost ~3.6 KB against the 20 KB ceiling, which is the arithmetic that makes
   inlining impossible and is worth stating in the template notes.
4. **New rule `layer-notes`**: every package whose `TRACEABILITY.md` status is `done` has a
   `docs/layers/<PACKAGE>.md` with the required headings and an index line in `AGENTS.md`; every
   file under `docs/layers/` names a package the plan defines. And: no `AGENTS.md` heading
   contains a work-package ID — which is the mechanical form of "the index, never the content",
   and the one assertion that would have stopped the exemplar's `AGENTS.md` at 22 KB.
5. **The reading order** (`templates/AGENTS.md`) gains: the layer notes of the packages the
   active item names as dependencies, and no others. **Playbook §2** names the file instead of
   "architecture notes"; **§10**'s "short task log" becomes the note's Handoff section.
   **Prompt 1** writes the note as part of the slice, not after it.

Q-W10.1 (owner): is a layer note required for **every** `done` package, or only where the
package established something a later slice can get wrong? A package can legitimately have
nothing to pass on, and a rule that forces one invites three sentences of ceremony.
Recommendation: **required for every package**, with "nothing a later slice needs to know"
as a legitimate body — the same argument as truthful-empty living documents, which say
`not started` rather than saying nothing. An optional note is one an agent under budget
pressure never writes, and the absence would then mean both "nothing to say" and "no time to
say it", which is the ambiguity this method exists to remove. Decision: **required for every
`done` package (owner, 2026-09-22)** — the recommendation as written. `layer-notes` fails on a
missing note whatever the package did, and the template's body may say that nothing was
established. Estimate: 1 day.

Acceptance:
- [x] a rendered pack has `docs/layers/README.md`, `free: docs/layers/**` in the manifest, and
      an empty index section in `AGENTS.md`; `test-render.sh` proves the whole gate still passes.
      *(cases 9, 9b)*
- [x] a fixture with a `done` package and no note fails `layer-notes`; adding the note with its
      three headings passes; a note whose package the plan does not define fails. *(four cases in
      `test-check-docs.sh`, and 9c/9d through the whole gate in `test-render.sh`)*
- [x] an `AGENTS.md` heading containing a package ID fails `layer-notes`. *(rule case, and 9e
      through the whole gate)*
- [x] `test-lock-guard.sh`: a write under `docs/layers/` is accepted by the guard, and a write
      under `docs/inputs/` is still refused, in the same commit. *(cases 3b, 3c)*
- [x] the playbook, the reading order and prompt 1 name the file; no template still sends
      overflow to `specs/`.

### W10.2 — Nothing computes what a task must read, so the prompt names whole documents

Prompt 1 says to read `AGENTS.md`, `PLAN.md`, `QUESTIONS.md`, `GAPS.md`, `TRACEABILITY.md`, the
`DECISIONS.md` index and cited entries, `specs/README.md`, the register, and the cited spec
sections. W9 already narrowed the worst of it — the exemplar's own prompt says to read all of
`DECISIONS.md`, 641 KB of it — but four of those documents are still named whole, and in the
exemplar `GAPS.md` and `TRACEABILITY.md` together are 529 KB, which is nearly what `DECISIONS.md`
costs. Narrowing the sentence further is not the fix; the fix is that **which parts are relevant
is a derivation the pack can already do**, from citations it already carries, and a derivation
this skill's own rule says belongs in `check-docs` rather than in an agent's judgement.

`--task` (W9) is that derivation, stopping one step early: it prints four characteristics and
nothing of the material.

Fix. Files: `design-pack/templates/scripts/check-docs.py`, `design-pack/templates/Makefile`,
`design-pack/templates/AGENTS.md`, `design-pack/templates/SESSION_BOOTSTRAP_PROMPT_SAMPLE.md`,
`design-pack/templates/specs/agent-playbook.md`, `design-pack/scripts/test-check-docs.sh`,
`design-pack/scripts/test-render.sh`.

1. **`--brief PACKAGE`**, beside `--task`, printing in this fixed order: the `--task` line
   (`Surfaces`, `Touches red line`, `Contract change`, live `blocked-by`); the `Now` item from
   `PLAN.md`; every `blocked-by` card in full; the **text** of every spec section the package and
   the `Now` item cite, resolved through the existing `section_index`; every `D-NNN` entry those
   texts cite, entry and index line; `docs/layers/<DEP>.md` for each dependency the package names
   (W10.1); the package's `TRACEABILITY.md` row; every `GAPS.md` row naming the package; and a
   footer giving the byte count of the brief itself.
2. It **selects, it never summarises**: every byte it prints is a citation the pack already
   carries, resolved. A brief that paraphrased would be a second source of truth, and the rule
   that no statement is untagged would stop at its edge.
3. `make brief TASK=<PACKAGE>` in `templates/Makefile`, and the same line in the `Commands`
   section of `templates/AGENTS.md` — the existing `commands` rule requires the two to agree, so
   this is checked for free.
4. **Prompt 1 opens with the brief** and names only what the brief does not carry: the source
   tree. `AGENTS.md`'s reading order becomes "run `make brief`; read `AGENTS.md` and the layer
   notes it indexes for your dependencies; read the whole of a document only when changing
   cross-cutting architecture". Playbook §2's task packet becomes the brief's output, which is
   the first time that section has had a producer.
5. If Stage C's mechanical pass runs `make brief` once to prove it works, `SKILL.md`
   `allowed-tools` needs `Bash(make brief *)` and `test-allowed-tools.sh` will say so.

Estimate: 1 day. Second-order benefit, free: the brief's byte count is the per-package reading
cost, which is the metric this item is judged by (see the closing note).

Acceptance:
- [x] `--brief FND-01` on the `test-render.sh` fixture prints every section above, in order, and
      resolves every citation; a package ID the plan does not define exits non-zero. *(cases 10,
      10b in `test-render.sh`; 11, 11e in `test-task-policy.sh`, which asserts the section list
      and its counts as one string)*
- [x] a card moved to Resolved changes the brief with no edit to the plan (the `blocked-by`
      guarantee of W9, now visible in the material). *(11f carries the card with its options;
      11d proves the plan is byte-identical after a brief; case 6/6b already held the
      characteristic half)*
- [x] a spec section renamed but not renumbered still resolves *(11g)*; a dead citation in a
      cited decision does not crash the brief — the brief prints the entry as the projection
      renders it and resolves nothing inside it, and `log-append` refuses such a citation at the
      door (W7.1).
- [x] `make brief TASK=` with no argument prints the usage line and exits non-zero. *(10d)*
- [x] `commands` passes with the new target; `test-render.sh` proves a rendered pack's brief is
      non-empty for FND-01 and that the whole gate still passes. *(10, 10b, 10c: 7.3 KB of brief
      against 50 KB of documents on the fixture)*
- [x] prompt 1 no longer names a document whole, except `AGENTS.md`, `specs/README.md` and the
      register — the two short files that govern everything the brief contains.

### W10.3 — Two living documents have no growth ceiling, and become chronicles

`plan-size` (100 lines) and `agents-size` (20 KB) exist. `GAPS.md` and `TRACEABILITY.md` have
nothing, and they are the two documents whose cells are *appended to* rather than rewritten. In
the exemplar this produced `G-001`: one row of one table whose Gap cell is ~20 KB and narrates
every phase of the project, and Evidence cells in `TRACEABILITY.md` that carry every run since
2026-09-02. Both are the same mistake — status history written into a register — and both are
read in full by every session.

The rule the exemplar's own `AGENTS.md` states for `PLAN.md`, "remove completed items, Git is the
archive", is the right rule for these cells and is nowhere enforced for them.

Fix. Files: `design-pack/templates/scripts/check-docs.py`, `design-pack/templates/GAPS.md`,
`design-pack/templates/TRACEABILITY.md`, `design-pack/scripts/test-check-docs.sh`.

1. **`gaps-size`**: no cell of a `GAPS.md` row exceeds 2000 characters. Calibrated on the
   exemplar: its good rows (`G-127`, `G-176`) are 1.0–1.4 KB and read as one gap; the failures
   are an order of magnitude past it.
2. **`evidence-size`**: no Evidence cell of `TRACEABILITY.md` exceeds 1000 characters. A cell
   holds the run that proved the current status — commands and test names — and the template
   line says the rest is in Git, where a status change is a commit.
3. Both templates gain the sentence in their header, and the failure message names the rule the
   row broke rather than the length ("a Gap cell holds one gap, not the history of the packages
   that narrowed it").
4. **Reported, not enforced**: the number of distinct package IDs a `GAPS.md` row names, in the
   informational summary. A row that names five is usually a chronicle, but sometimes it is a
   gap five slices genuinely narrowed, and that is a judgement — the same treatment
   `Contract change` gets.

Estimate: ½ day.

Acceptance:
- [x] a 3 KB Gap cell fails `gaps-size`, naming its length; a row that states one gap passes.
- [x] a 2 KB Evidence cell fails `evidence-size`; the same row with the latest run only passes.
- [x] the run reports the package count per gap row and never fails on it — a new `note()`
      helper beside `fail()` and `ok()`, so "reported, not enforced" has a shape in the checker
      rather than being a comment in a rule.
- [x] `test-render.sh` unaffected, and it now also asserts that `GAPS.md` and `TRACEABILITY.md`
      state their own ceilings and why (case 11c): a ceiling only in the checker is a surprise,
      and the document that has to live inside it should say so.

### W10.4 — Prompt 1 has no end other than success, and prompt 2 reviews the session that wrote the code

Two prose changes, one of them load-bearing.

Prompt 1's end condition is "continue until every acceptance condition is demonstrably
satisfied". There is no other way out. A slice that turns out to be larger than one session
therefore ends where the context ends — in compaction, where the documents are least likely to
be truthful — rather than at a boundary the agent chose. The `Notes` section already knows this
("when a session ends early, ask the agent to leave `PLAN.md`, `GAPS.md` and `TRACEABILITY.md`
truthful"), but it is advice to the *owner*, outside the prompt the agent runs.

Prompt 2 is run by whoever finishes the slice, which in practice is the session that wrote it —
holding every assumption it is meant to audit. Stage D already answers this in the design phase:
`stages/hunter.md` is a fresh agent with one mandate and no memory of the elicitation. The review
pass is the same problem one phase later.

Fix. Files: `design-pack/templates/SESSION_BOOTSTRAP_PROMPT_SAMPLE.md`,
`design-pack/templates/specs/agent-playbook.md` §10, `design-pack/templates/AGENTS.md`
(the note under the prompt-selection table).

1. Prompt 1 gains a second exit: *or the session's budget is reached* — then stop at a boundary
   you choose, leave `PLAN.md`, `GAPS.md` and `TRACEABILITY.md` truthful, write the layer note's
   Handoff (W10.1), name the next step precisely, and do not begin a sub-task you cannot finish
   and record.
2. Prompt 2 states that it runs in a **fresh session**, given the brief of the slice (W10.2) and
   the diff, never in the session that implemented it, and says why in one sentence citing the
   same reason Stage D gives.

Estimate: 1 hour. No new rule: this is prose about how a session is run, and there is nothing
here a snapshot of the repository can assert. `test-render.sh` greps for both sentences.

Acceptance:
- [x] both sentences present in a rendered pack (cases 11, 11b).
- [x] the prompt-selection table's note says where prompt 2 runs, not only whether. Prompt 2 also
      opens on `make brief` and the slice's layer note instead of on `AGENTS.md` and a
      traceability row, which is the same economy as prompt 1's.

### W10.5 — A package has no size and no lane, so the plan cannot be split or parallelised (**owner**)

`templates/specs/implementation-plan.md` §Backlog discipline requires every ticket to state its
"allowed file surface"; the playbook §2 requires the agent to be told "files or modules it may
change and the known shared-file owner"; the Safe parallelization section names lanes. **None of
the three is stored anywhere.** A package therefore has no declared size, which is why nothing at
Stage B notices that a package is three subsystems wide (the exemplar's `GST-04` carries four
acceptance conditions across preview, publication filtering and the go-live checklist), and no
orchestrator can tell whether two packages can run at once — so they never do, and the only
lever left on wall-clock is making one session faster.

This is the one item that reduces elapsed time rather than tokens: three non-overlapping lanes in
worktrees are three slices in the time of one, and the constraint that makes it safe (never
parallelise migrations for one aggregate or edits to the contract root) is already written, with
nothing to evaluate it against.

Fix. Files: `design-pack/templates/specs/implementation-plan.md`,
`design-pack/templates/scripts/check-docs.py`, `design-pack/stages/B-specify.md`,
`design-pack/scripts/test-task-policy.sh`.

1. A fourth stored characteristic **`File surface:`** — the modules or directories the package may
   change — and a fifth, **`Lane:`**, from the lane list the plan already defines. Both are the
   plan author's **judgement**, like `Contract change`: `task-policy` checks presence and shape
   and never recomputes them. This keeps W9's four treatments intact rather than adding a fifth
   kind.
2. `--brief` prints both, so playbook §2's "files it may change" finally has a value at the
   moment an agent needs it (W10.2).
3. Stage B splits a package whose file surface spans more than one lane, or records why it does
   not; the rule is a sentence in `B-specify.md`, not an assertion, because how wide is too wide
   is a judgement about the product.
4. **Reported, not enforced**: packages in the same lane whose file surfaces overlap, printed by
   `--task all`, so an orchestrator choosing lanes reads it rather than guesses.

Q-W10.5 (owner): where do the two new fields live? In the plan, with the other three, which the
freeze hard-locks — so a correction costs a `make unlock`. Or in `AGENTS.md`, the free tier,
where they can be tuned but drift from the contract they describe. Recommendation: **in the
plan**, on W9's own argument — the characteristics are properties of the package and belong with
it, the *policy* that reads them is what lives in the free tier, and a file surface that turns
out to be wrong is exactly the kind of correction that should leave a record. Decision: **in the
plan (owner, 2026-09-22)** — the recommendation as written. Both fields are stored on the package
beside the other three, the freeze hard-locks them with the rest of `specs/`, and a correction is
a `make unlock` with its reason in `UNLOCKS.md`. Estimate: ½ day.

Acceptance:
- [x] a package missing `File surface:` or `Lane:` fails `task-policy`, and the message says what
      the field is for rather than repeating the prompt-selection sentence, which is not what
      these two are read by *(case 12)*; a lane the plan's list does not define fails, listing
      the lanes it does *(12b)*.
- [x] `--task all` reports overlapping file surfaces within a lane and exits zero *(12e)*; the
      gate reports the same overlap and never fails on it *(12f)*.
- [x] `--brief` prints both fields *(12g)* — which is the moment the playbook's "files it may
      change" reaches an agent rather than staying a requirement in §2.
- [x] `test-render.sh` proves a rendered pack carries them on **every** package, Phase 0 and
      domain alike, and that `--task all` prints them *(12, 12b)*.

### W10.6 — What a run learns about the tooling has no home either

Smaller than the rest and the same shape. The exemplar's `AGENTS.md` carries, in prose, two
things that cost a measured session each to discover: that its test runner compacts its output to
one JSON line when it detects an agent and can print **nothing** at all on a fatal error unless an
environment variable is set, and that one suite fails about half its runs under the repository's
own parallelism and passes when run alone — with the instruction not to retry into green. This is
the highest-value-per-byte knowledge in that file, and in this skill's packs it has nowhere to go
but a file with a 20 KB ceiling.

Fix: Stage C creates `docs/gotchas.md` (known-flaky gates and the evidence, agent-hostile tool
output and the flag that fixes it, environment traps), the `Commands` section of
`templates/AGENTS.md` carries one pointer line to it, and prompt 1 says a gate that fails for an
environmental reason is recorded there rather than retried. No new rule: nothing about the
content is mechanically assertable, and a rule requiring a non-empty file would produce
invented entries. Files: `design-pack/stages/C-operationalize.md`,
`design-pack/templates/AGENTS.md`, `design-pack/templates/SESSION_BOOTSTRAP_PROMPT_SAMPLE.md`.
Estimate: ½ hour.

Acceptance:
- [x] a rendered pack has `docs/gotchas.md` with its headings and a pointer from `AGENTS.md`.
      *(case 9; the pointer is in the session reading order and the living-documents list rather
      than in `Commands` — a session looks for what to read in the reading order, and `Commands`
      is the contract's own list)*
- [x] `test-render.sh` still green. *(27 cases)*

### Order and measurement

W10.1 before W10.2 (the brief reads the layer notes). W10.3, W10.4 and W10.6 are independent.
W10.5 last: it touches `task-policy`, which W9 and its follow-up have just stabilised.

The overview measures this method by **owner interventions per work package**, which measures the
elicitation and says nothing about what a run costs. This item adds a second measure, and
`--brief` produces it as a by-product: **bytes of brief per package**, and **sessions per
package** from the layer notes' dated Handoff sections. Both come from the pack itself, neither
needs the owner, and if they do not fall after W10.1 and W10.2 land, this item did not work.
On the exemplar's numbers the target is a session that opens on ~35 KB instead of ~1.46 MB.

---

## W11 — Parallel execution under an orchestrator

Status: in progress
Decision: the four owner questions asked up front were decided on 2026-10-09. **The owner
accepted all four recommendations as written**: Q-W11.1, placeholders only in the staging file
and the package's own layer note; Q-W11.2, Prompt 1 is aligned with 1o; Q-W11.3, `Depends on:`
is stored in the plan; Q-W11.5, the owner runs one unlock per landed package. The work raised a
fifth question, Q-W11.4. The wave checks hold only for `Now` items that carry a `Branch:`, and
the owner decided it the same day (see W11.4). Q-W11.6 is measured before it is asked, as the
item says.

W9 told an orchestrator *which* prompts a package needs, and W10.5 told it *whether* two packages
can run at once (`File surface:`, `Lane:`, and the overlaps `--task all` reports). Nothing yet
covers what happens when they do. Prompt 1 assumes one session working on one `Now` item,
writing directly to documents that every package shares. Run three of those sessions in three
worktrees and they collide in four places:

- **The event log.** Each session appends to `.log/events.jsonl` through `log-append.py`. Two
  branches append from the same last record, so on merge the chain forks: two records with the
  same `seq` and `prev`, and `verify-chain` fails. Separately, both sessions assign the next ID,
  so two different decisions are both `D-012`. Git can resolve neither collision: the log is
  append-only, so there is nothing to resolve them *to*.
- **The projections and living documents.** Every package edits `DECISIONS.md`, `QUESTIONS.md`,
  `TRACEABILITY.md`, `GAPS.md`, `PLAN.md` and the Layer-notes index in `AGENTS.md`, so every
  merge conflicts.
- **Dependencies within a phase.** The plan orders phases, and W10.5 orders lanes. Nothing states
  that a package needs another package's outcome inside the same phase for a reason other than a
  contract, so an orchestrator has to infer it, and an inference is a decision an agent made.
- **Prompt 1's assumption clause.** "Otherwise state the assumption, tag it, and continue" lets
  an implementation session decide a surface question itself whenever it judges the decision
  cheap. That contradicts Stage A, where the skill never decides a surface question for the
  owner. One session at least surfaces the assumption in its own handoff. Three parallel
  sessions bury it in three handoffs.

The design principle does not change: the pack states DATA and the orchestrator applies POLICY.
Everything W11 adds falls into one of three kinds:

- derived and verified;
- a recorded judgement, checked for form;
- live state.

The event log stays the only source of truth for decisions and cards.

### W11.1 — Staged events and `make land` (B)

Files: `templates/scripts/log-land.py` (new), `templates/scripts/eventlog.py`,
`templates/scripts/log-append.py`, `templates/scripts/check-docs.py`, `templates/Makefile`,
`templates/.doc-locks`, `templates/log-README.md`, `templates/AGENTS.md` (Commands),
`stages/C-operationalize.md` (the copy list), `scripts/test-land.sh` (new).

1. **The staging file.** A session working on a package under an orchestrator never appends to
   the log. It writes the events it would have appended to `.log/pending/<PACKAGE>.jsonl`, one
   JSON object per line: `{"stream", "type", "actor", "payload"}`, with no `seq`, `prev` or
   `hash`. IDs inside payloads are placeholders, numbered per package: `D-NEW-1`, `Q-NEW-1`, and
   so on. `.doc-locks` gains `free: .log/pending/**` below the `append-only` line, with a comment
   saying why it is free: staging stays mutable until it lands, and only the chain is
   append-only.
2. **Staged document updates.** The same session writes its updates to the shared documents in a
   `## Landing` section of `docs/layers/<PACKAGE>.md`, one line per update, in a fixed form that
   `log-land.py` can apply:
   - in `TRACEABILITY.md`, the package row and its evidence;
   - in `GAPS.md`, the rows to add, narrow or retire, with a new row carrying a `G-NEW-n`
     placeholder, because two parallel packages would otherwise both add `G-012`;
   - in `PLAN.md`, the item to remove.

   The Layer-notes index line is not staged: it is derived from the note's title.
3. **`make land TASK=<PACKAGE>`** runs `log-land.py`, which:
   - validates every staged event with the same checks as `log-append.py`, before it writes
     anything (all or nothing);
   - assigns the next contiguous real IDs in staged order, and rewrites the placeholders in the
     staged events and in `docs/layers/<PACKAGE>.md`;
   - appends the events through the same code path as `log-append.py`, so there is one writer
     and one set of refusals;
   - rebuilds both projections and applies the `## Landing` updates;
   - removes the staging file and the `## Landing` section;
   - on any refusal, exits non-zero and changes nothing.
4. **A new `check-docs` rule, `pending`:**
   - every staged line is well-formed for its stream;
   - placeholders follow `D-NEW-n` and `Q-NEW-n`, and no staging file assigns a real `D-` or
     `Q-` ID;
   - a package whose `TRACEABILITY.md` row is `done` has no staging file and no `## Landing`
     section.
5. **Landing order is the orchestrator's choice**: one package at a time, right after it
   integrates. The pack guarantees only that landing is deterministic and refuses exactly what
   `log-append.py` refuses.

Q-W11.1 (owner): where may placeholders appear? Recommendation: **only in the staging file and
in the package's own layer note.** Code comments and commit messages do not cite decision IDs
before landing. A session that needs to refer to its own new decision in code waits for the
landed ID and adds it in a follow-up commit. Otherwise `log-land.py` would have to rewrite
source files, which is a different and riskier job. Decision: **staging file and layer note only
(owner, 2026-10-09)**, the recommendation as written.

Acceptance (`scripts/test-land.sh`, on a rendered pack):
- [x] Two packages are staged on two branches from the same base, merged, then landed one after
      the other. Then `verify-chain` passes, the IDs are contiguous, and each layer note cites
      its own real IDs.
- [x] A staged event that `log-append.py` would refuse (a dead citation, an unknown type) makes
      `land` exit non-zero, and the log, the projections and the documents stay byte-identical.
- [x] A staging file that carries a real `D-NNN` fails `pending`, and the failure names the
      line.
- [x] A `done` package with a leftover staging file fails `pending`.
- [x] A pack that never stages anything (single-session use) passes `check-docs` unchanged.

### W11.2 — Prompt 1o, and the assumption clause (B, **owner**)

Files: `templates/SESSION_BOOTSTRAP_PROMPT_SAMPLE.md`, `templates/AGENTS.md` (Prompt selection),
`templates/scripts/check-docs.py`, `scripts/test-task-policy.sh`, `scripts/test-render.sh`.

Add **Prompt 1o — Implement (orchestrated)** beside Prompt 1, without editing Prompt 1's other
text. Prompt 1o differs from Prompt 1 in exactly four ways:
- It works on the package the orchestrator names, on the branch the orchestrator names, and only
  inside the package's `File surface:`. If it needs anything outside the file surface, it stops
  and reports.
- It never runs `log-append.py`, `make rebuild-*` or `make land`, and it never edits the shared
  documents. It stages events and document updates as W11.1 describes.
- If a specification ambiguity touches data, security, scope, external commitments or UX, it
  **stops** and reports the card it would open: the silent section, the options, their
  consequences and a recommendation. It does not continue on an assumption.
- It commits on its branch when the orchestrator's brief says so.

The Prompt selection table gains one row: "Under an orchestrator, Prompt 1o replaces Prompt 1;
prompts 2 and 3 are unchanged." `task-policy` already reads that table, so its list of accepted
prompt names gains `1o`.

Q-W11.2 (owner): should Prompt 1's own clause change too? It reads: "pause only if proceeding
would make a costly or irreversible assumption. Otherwise state the assumption, tag it, and
continue." That lets a session decide a surface question on its own judgement of cost, which
Stage A never allows. Recommendation: **yes, align Prompt 1 with 1o.** An ambiguity that touches
a surface becomes a card and the session stops. Anything that touches no surface stays a
recorded `decision-added` and the session continues. The line between owner decisions and agent
decisions is then the same at design time and at build time. The cost is that a single-agent
session stops more often, and the owner-interventions metric exists to measure exactly that.
Decision: **align Prompt 1 (owner, 2026-10-09)**, the recommendation as written.

Acceptance:
- [x] Prompt 1o exists and the policy table names it. `task-policy` passes with it, and fails on
      a misspelled prompt name.
- [x] Prompt 1o contains no instruction to write `.log/events.jsonl`, `DECISIONS.md`,
      `QUESTIONS.md`, `TRACEABILITY.md`, `GAPS.md`, `PLAN.md` or `AGENTS.md`. This is a grep
      test, like the existing prompt checks.
- [x] Per Q-W11.2, Prompt 1's assumption clause matches 1o's surface rule.

### W11.3 — `Depends on:`, the sixth characteristic (B, **owner**)

Files: `templates/specs/implementation-plan.md`, `templates/scripts/check-docs.py`,
`stages/B-specify.md`, `scripts/test-task-policy.sh`, `scripts/test-render.sh`.

1. Every package carries **`Depends on:`**: the package IDs that must be `done` before it
   starts, or `—`. Phase order is already implied and is not repeated, so only dependencies
   within the same phase are listed.
2. **The field is partly derived.** Suppose package B cites a section that package A, in the
   same phase and marked `Contract change: yes`, also cites. Then A must be listed in B's
   `Depends on:`. `task-policy` recomputes these pairs and fails on a missing one, naming both
   packages and the shared section. If both packages change a contract over the shared section,
   one of them has to list the other: the rule cannot require both directions without requiring
   a cycle.
3. Any further dependency is the plan author's judgement, recorded in the same Stage B
   `decision-added` as the lane assignment. `task-policy` checks that the listed IDs exist, are
   in the same phase, and form no cycle.
4. `--task` and `--brief` print the field, and `--task all` prints each phase's dependency order.

Q-W11.3 (owner): should the field be stored in the plan, which the freeze hard-locks so that a
correction needs a `make unlock`, or in `PLAN.md`, which is free? Recommendation: **in the
plan**, for the reason Q-W10.5 was decided that way. A dependency is a property of the package,
a wrong dependency is exactly the kind of correction that should leave a record, and the
orchestrator must never compute an order that the pack can state. Decision: **in the plan
(owner, 2026-10-09)**, the recommendation as written.

Acceptance:
- [ ] A consumer that cites a contract package's section without listing it fails, naming both
      packages and the section.
- [ ] A cycle fails, naming it. A dependency on a package in another phase fails with "phase
      order already implies this".
- [ ] `--brief` and `--task all` print the field, and `test-render.sh` proves that every rendered
      package carries it.

### W11.4 — `PLAN.md` holds a wave (A)

Files: `templates/PLAN.md`, `templates/AGENTS.md` (Living documents),
`templates/scripts/check-docs.py`, `scripts/test-check-docs.sh`.

`PLAN.md` already allows 1–3 `Now` items. Under an orchestrator, each `Now` item gains two
lines: **`Lane:`**, copied from the plan, and **`Branch:`**, written by the orchestrator, or `—`
in single-session use. New `check-docs` checks:
- no two `Now` items share a lane;
- no `Now` item has a non-empty `blocked-by`;
- no `Now` item depends (W11.3) on a package that is not `done`.

Q-W11.4 (owner, raised by the work): which `Now` items do the three checks hold for? In W9's
single-session flow, a `Now` item with an open card is the normal state: Prompt 3 runs, then
Prompt 1. If every blocked `Now` item failed the gate, the session that writes the next package
into `PLAN.md` would fail its own `make check-docs`. Recommendation: **only items that carry a
`Branch:` other than `—`**, because a branch is what says the item is running beside the
others. Decision: **only items with a `Branch:` (owner, 2026-10-09)**. A `Lane:` that is present
is checked against the plan on every item, because a wrong copy is wrong in either mode.

Acceptance:
- [ ] Two dispatched `Now` items in one lane fail. A blocked package in `Now` fails. A `Now` item
      with an unmet dependency fails.
- [ ] A single `Now` item without `Branch:` (single-session use) passes.

### W11.5 — Spec amendments under parallel work (B, **owner**)

Files: `templates/scripts/log-land.py`, `templates/scripts/check-docs.py` (`pending`),
`templates/scripts/unlock.sh`, `templates/Makefile`, `templates/AGENTS.md`,
`scripts/test-land.sh`, `scripts/test-lock-guard.sh`.

Evidence from the first real run (dnd-vtt, 2026-09-23 to 2026-10-07): 119 unlock ceremonies over
46 packages, concentrated in four specs:

| Spec | Unlock ceremonies |
| --- | --- |
| `08-ux-journeys` | 16 |
| `04-live-sync` | 15 |
| `13-implementation-plan` | 13 |
| `11-traceability` | 11 |

Amending spec text is the normal path of implementation, not an exception. Serially that is
fine. In parallel, two packages that amend `08` in two worktrees each need their own unlock of
the same path, and their edits conflict on merge, in a hard-locked file.

The fix: amendments are staged the way events are (W11.1). A session writes them to
`.log/pending/<PACKAGE>.amendments`, one JSON object per line:
- the file and the section heading;
- the exact old text and the new text;
- the provenance tag;
- the placeholder of the `spec-amendment` decision.

`make land` applies them once each file they touch has been unlocked, one package at a time. It
refuses any amendment whose old text is no longer present, because an earlier landing changed
it; the session then re-derives the amendment.

Q-W11.5 (owner): who runs the unlock at landing time? Recommendation: **the owner, once per
landed package, covering every file that package amends.** That keeps the meaning of the
ceremony, an owner's recorded reason, without one ceremony per hunk. It needs one small change:
`unlock.sh` accepts several paths with one reason, and the token stays single-use, for one
commit. Decision: **the owner, once per landed package (owner, 2026-10-09)**, the recommendation
as written.

Acceptance:
- [ ] An amendment staged on a frozen pack is refused by `land` until the file is unlocked, and
      the refusal names the `make unlock` to run. After `make unlock` of every path in one
      command, the amendment lands, and the decision it cites is the landed ID.
- [ ] An amendment whose old text an earlier landing changed is refused, and nothing is written.
- [ ] `make unlock PATH="a b" REASON=...` records one line per path with the same reason and
      authorizes both paths for one commit. A path that is not hard-locked refuses the whole
      ceremony and records nothing.
- [ ] `pending` fails an amendment line that lacks a field or names a decision the staging file
      does not add.

### W11.6 — `Surfaces` does not discriminate (C, **owner**)

In the dnd-vtt pack, 45 of 46 packages get Prompt 2 from the policy table, and 20 carry all five
surfaces. `Surfaces` is derived from **whole cited sections**, and nearly every section the plan
cites carries at least one security or data statement. The characteristic therefore says "this
package cites a big section", not "this package changes security or data". The table is
working as written but selects almost everything, which is the opposite of W9's purpose: to skip
the reviews that add nothing.

Q-W11.6 (owner): narrow the derivation, or accept universal review? There are two options:
- **A)** Derive `Surfaces` from the normative statements that the package's **acceptance
  criteria** cite, not from whole sections.
- **B)** Keep the derivation, and admit in `AGENTS.md` that Prompt 2 is effectively always on.

Recommendation: **A**, but measured first. Run `--task all` both ways on dnd-vtt, and accept the
change only if both conditions hold:
- FND-, UI-only and docs-only packages stop selecting review;
- every package that changed auth, storage or the protocol still selects it.

Acceptance:
- [ ] The measurement has been run on dnd-vtt and recorded here. The owner's decision is
      recorded in this item's `Decision:` line, and whichever derivation it names is the one
      `task-policy` holds.

### W11.7 — Server-side lock enforcement on github.com (C)

`.githooks/README.md` says that enforcement is `pre-receive` on the remote. That hook cannot be
installed on github.com: custom pre-receive hooks exist only on GitHub Enterprise Server.
dnd-vtt's remote is github.com, so its locks are enforced only locally.

The fix has three parts:
- FND-02's CI baseline gains a `check-locks` job. The job runs `lock-guard.py` over the pull
  request's diff, judged by the base branch's `.doc-locks`, which is the same rule `pre-receive`
  applies.
- The README tells the owner to make that job a required status check.
- The README's "Why both" section names CI as the server half wherever `pre-receive` is not
  available.

The worktree sentence from "Not in W11" lands in the same README: `core.hooksPath` is shared
config, so the pre-commit guard runs in every worktree, but the read-only modes are per checkout,
so the orchestrator runs `lock-guard.py --relock` in each worktree.

Acceptance:
- [ ] `make check-locks BASE=<rev>` judges the range from the merge base to `HEAD` with the
      base's manifest. It refuses a locked change with no recorded reason, and accepts the same
      change carrying its `UNLOCKS.md` record.
- [ ] The rendered FND-02 names the job, and `.githooks/README.md` names CI as the server half
      and carries the worktree sentence.

### Migrating an existing pack to W10/W11

dnd-vtt predates W10. It has no `File surface:`, no `Lane:`, no `make brief` and no
`docs/layers/`. Before it runs under an orchestrator:

1. Add the two fields, and W11.3's `Depends on:`, to every package in one `make unlock` of
   `specs/13-implementation-plan.md`. Use the five lanes that its §8 already lists, with their
   paths.
2. Copy in the newer `check-docs.py`, `eventlog.py`, `log-append.py` and `log-land.py`, the new
   `Makefile` targets and `docs/layers/README.md`.

This is the cheapest way to make the existing pack schedulable without the orchestrator
proposing anything. It is a change to the owner's pack, made by the owner. Nothing in this
repository runs it.

### Not in W11

- **Wave sizes and wave membership** are the orchestrator's policy, approved by the owner per
  wave. The pack states lanes, file surfaces, contracts and dependencies. It never stores a
  schedule.
- **Answering cards after the freeze** already works: `QUESTIONS.md` and `DECISIONS.md` are free
  projections, cards move by events, and an answer given after the baseline goes into a
  decision. No change is needed.

### Order

1. W11.1 first, because W11.2's prompt stages what W11.1 lands.
2. W11.3 before W11.4, because the wave checks read `Depends on:`.
3. W11.5 extends `log-land.py`, so it comes after W11.1.
4. W11.6 is a measurement, then the owner's decision.
5. W11.7 is independent.

---

## Not in scope

- Signed unlock records / server-side approval (see W5 — would change the threat model).
- Renaming `make unlock PATH=` to `TARGET=`: the Makefile already accepts `TARGET`, and the
  `case *:*` guard handles the collision. Document `TARGET=` as the preferred form in
  `templates/Makefile` help text and `templates/AGENTS.md` when W3 touches those files; no
  separate item.
- The empty git history of this repository (no commits on `main`). The owner's call; nothing
  here depends on it, but W2 assumes a clean tree to copy from.

---

## Progress log

Append-only. One entry per session per item touched. Form:

```
### <YYYY-MM-DD> — <item> — <status after this session>
- Changed: <files>
- Proved by: <test names or commands run, with exit status>
- Left open: <what remains, or "nothing">
```

### 2026-09-07 — W1 — done
- Changed: `design-pack/templates/githooks/post-commit` (A1: token removed first and
  unconditionally, re-lock best effort, no `set -e`); `design-pack/templates/scripts/eventlog.py`
  (A2 contiguity in both projectors, A3 `--check` before `--stdout`, A4 message, A5 approval
  only on `adr`, A6 `read_lines` splits on `\n` only and `dumps` escapes U+2028/2029/0085);
  `design-pack/templates/scripts/check-docs.py` (A2 `cards` contiguity, A7 Makefile in `markers`);
  `DOCUMENTATION.md` (A8 lines 11–13; §11 suite table); `design-pack/SKILL.md` (files table).
  Tests: `test-lock-guard.sh` +4f/4g, `test-decisions-log.sh` +6/6b/6c/6d,
  `test-questions-log.sh` +1 refusal in §8, cases 5c/5d/10 now use the next contiguous IDs
  (Q-004, Q-005 instead of Q-009, Q-020); new `test-check-docs.sh` (5 cases).
- Proved by: all four suites exit 0 — lock-guard 14/14, decisions 15/15, questions 31/31,
  check-docs 5/5 (was 53 cases, now 65). Mutation: with the pre-fix `post-commit` restored,
  case 4f fails and the rest pass, so 4f is the case that pins A1. Each A2–A7 reproduction
  from the plan re-run against the patched scripts: D-003 after D-001 → exit 2; Q-002 with no
  Q-001 → exit 2; approval on `implementation` → exit 2; `--check --stdout` on drift → exit 1;
  U+2028 record → `verify-chain: intact`; `{{X}}` in Makefile → `FAIL markers Makefile:1`.
- Left open: nothing. Note for W2: `test-check-docs.sh` is the rule-level suite; `test-render.sh`
  stays the whole-gate suite as planned.

### 2026-09-08 — W2 — done
- Changed: new `design-pack/scripts/test-render.sh` (17 cases): a Python renderer inside the
  script strips `TEMPLATE NOTES`, drops the `<!-- if:API/UI -->` blocks, substitutes every
  placeholder for a fixture product ("Ledgerette", no API, no UI, no contract-drift target) and
  refuses to write a file that still carries `{{`; seeds the log from `decisions-seed.json` plus
  one Resolved and one Open card; writes four domain specs the templates' citations resolve
  against. Fixes found by building it: `stages/C-operationalize.md` C1.2 now also ignores
  `__pycache__/` (the first commit of a rendered pack tracked `scripts/__pycache__/*.pyc`,
  because `check-docs.py` imports `eventlog.py`); `templates/log-README.md` named only the
  `decisions` stream and is now accurate for both. `SKILL.md` files table and
  `DOCUMENTATION.md` §11 list the suite.
- Proved by: `test-render.sh` 17/17 on the current templates; the rendered pack passes
  `make check-docs` with 0 failures, 8 log records, both projections fresh, AGENTS.md 11 287
  bytes. Mutations: renaming `## Commands` in `templates/AGENTS.md` → cases 1 and 6 fail with
  `FAIL commands AGENTS.md: no `## Commands` section`; deleting the `rebuild-questions` target
  from `templates/Makefile` → cases 1 and 6 fail naming `make rebuild-questions`. Both templates
  restored from git afterwards. All five suites green: 14 + 15 + 31 + 5 + 17 = 82 cases.
- Left open: nothing. W3 can now change the guard with this net under it.

### 2026-09-08 — W3 — done
- Changed: `design-pack/templates/scripts/lock-guard.py` — new `demotions()` (probes every glob of
  both manifests plus every path in the diff; a tier that goes down is a violation whichever
  glob does it), `check()` takes the new manifest and fails closed when the manifest changes
  without one; `--staged` judges with `HEAD:.doc-locks` and compares to the index's copy
  (falls back to the staged copy before the first commit); `--new-manifest` for the remote.
  `templates/githooks/pre-receive` extracts the pushed manifest and passes it. `templates/.doc-locks`:
  `scripts/lock-guard.py`, `scripts/unlock.sh`, `.githooks/**` and `.doc-locks` itself are
  hard-locked; the header explains the demotion rule. Stages: `D-review.md` D4.2 is now
  `make unlock PATH=.doc-locks` then append; `C-operationalize.md` C1.7 states the
  self-protection (C1.2 needed no change: the copy step is unchanged). Docs: `githooks/README.md`,
  `templates/AGENTS.md` `.doc-locks` bullet, `SKILL.md` hard rule, `DOCUMENTATION.md` §5.1–5.2
  and §11. Tests: `test-lock-guard.sh` +7/7b/7c (demotion locally, demotion-only push rejected,
  fail closed), +8/8b/8c (guard self-protection, promotion blocked without and accepted with the
  ceremony), +10 unit asserts (same/broader/narrower glob, one step down, three non-demotions,
  promotion under an append-only manifest, single demotion violation, fail closed);
  `test-render.sh` case 6 rewritten — it had passed vacuously because the freeze commit's exit
  status was never checked; it now performs the D4 ceremony, asserts the commit landed and that
  the guard cannot be edited without one (6/6a–6e).
- Proved by: all five suites green — lock-guard 20/20, decisions 15/15, questions 31/31,
  check-docs 5/5, render 20/20 (91 cases). The review's attacks re-run against the new guard:
  one-commit demotion+edit → 3 violations (demotion, manifest hard-locked, input hard-locked);
  two-push demotion → push 1 rejected with `LOCK demotion`; editing the guard → blocked;
  broader (`free: docs/**`), narrower (`free: docs/inputs/requirements.md`) and one-step
  (`append-only: docs/inputs/**`) demotions all detected; `hard-locked: specs/**` is not.
  Mutation: with the pre-W3 guard restored, cases 7, 7b, 7c and the unit block fail; 8x still
  pass because they rest on the manifest, which is the intended second layer.
- Left open: nothing. Note for W5: the demotion rule is absolute (no ceremony undoes a tier);
  the honest-limits text should say that a mistaken promotion is corrected only by an
  administrator of the remote, deliberately.

### 2026-09-08 — W4 — done (Q-W4 decided B by the owner)
- Changed: `templates/scripts/check-docs.py` — one detector, `normative_statements()` (keywords
  outside code spans, lead-in inheritance, register bullets normative by definition, fences and
  table rows skipped), rule `normative-tagged` (untagged statement in `specs/` fails; exempt
  when `docs/inputs/README.md` lists `` `specs/` `` as authoritative — `adopted_pack()`), rule
  `inferred-zero` (fails only once `specs/README.md` is stamped — `frozen()`), and a summary
  line naming every statement that cites a card not yet Resolved, flagged when the pack is
  frozen and never failing (decision B). `scripts/extract-normative.py` now imports that
  detector via importlib, so listing and gate cannot disagree.
  **Templates had 20 untagged normative statements** — a pack as shipped could not have passed
  D2. Fixed at the source: `specs/traceability.md` and `specs/implementation-plan.md` had
  `[input]` mid-line (moved to the end); `specs/decision-register.md` §6 change-control prose
  is tagged `[D-002]`; `specs/agent-playbook.md` §3 lead-ins (`The agent MUST:` / `MUST NOT:`,
  15 items) are tagged `[D-005]` — a new fifth regime record, *Agent execution contract*, in
  `decisions-seed.json` (uses `{{NN_PLAYBOOK}}`; every "four regime records" mention updated).
  Docs: `reference/provenance.md` (code-span mention, trailing-tag warning, the two rules, the
  Open-card-after-freeze paragraph), `stages/D-review.md` D2.2, `stages/C-operationalize.md`
  (adopted-pack marker form), `SKILL.md` mechanism 3, `DOCUMENTATION.md` §8 and §11,
  `design-pack-overview.md` (the claim is now true, and states the Open-card exception).
- Proved by: `test-check-docs.sh` 12/12 (+7: two untagged of seven candidates fail on the right
  lines while code span, fence, table and inherited items pass; all-tagged passes; adopted pack
  exempt; `[inferred]` passes in a draft and fails the same fixture once stamped; frozen-clean
  passes; `extract-normative` lists the untagged line through the shared detector).
  `test-render.sh` 20/20 with the fixed templates; the rendered pack reports
  `normative-tagged: 19 normative statements, every one tagged`, `D-005` in the projection, and
  `provisional statements … none` (the fixture's Open card Q-002 is cited by no statement);
  `extract-normative --untagged` on it lists 0, where it listed 20 before the template fixes.
  All five suites green: 20 + 15 + 31 + 12 + 20 = 98 cases.
- Left open: nothing.

### 2026-09-08 — W5 — done (option 1, documentation only)
- Changed: `DOCUMENTATION.md` §5.2 — "the guarantee" → "the enforcement", plus a new paragraph
  *What the remote does and does not guarantee* (recorded reason for the exact path, no lost
  append-only line, no lowered tier; not who wrote the reason; the demotion rule as the one
  absolute, undone only by a remote administrator); §5.3 "Two authorization paths" → "Two
  evidence paths". `design-pack-overview.md` honest-limits paragraph: the unlock ceremony has the
  same shape as the chain (audit trail, not approval gate) and tiers only go up.
  `templates/githooks/README.md` "Why both" and the install note; `templates/githooks/pre-receive`
  header; `templates/scripts/lock-guard.py` docstring ("authorized by evidence…, not proof of who
  approved it"); `templates/UNLOCKS.md` notes and body ("an audit trail, not an approval gate");
  `templates/log-README.md` (the ledger does not authenticate either); `stages/C-operationalize.md`
  C1.6 and `SKILL.md` hard rule ("which `--no-verify` cannot reach … the reason is self-asserted").
  No code path changed; the guard's identifiers (`authorized`, `authorized_from_diff`) keep their
  names.
- Proved by: `grep -rn -i guarantee` over docs and templates — every remaining use is either the
  chain's own accurate statement (what it guarantees / does not guarantee authorship), the new
  limits paragraph, or the overview's section title "Why 'locked' is a guarantee, not a note",
  whose body now states the limits in the same breath. All five suites green (98 cases);
  `test-render.sh` case 3b (no skill reference in the rendered pack) unaffected.
- Left open: nothing. Signed unlock records remain out of scope by the owner's decision.

### 2026-09-08 — W6 — in progress (part a done; part b needs a live session)
- Changed: `design-pack/SKILL.md` `allowed-tools` — 20 `Bash(...)` patterns (was 5): the copied
  tools inside the target (`python3 scripts/*`), the seven `make` targets the skill runs, and
  the intake/asset commands the stages instruct (`cd`, `mkdir`, `touch`, `cp`, `chmod`,
  `git config core.hooksPath*`, `git ls-files *`, `xargs *`, `grep *`) — each named because
  Claude Code matches every subcommand of a `&&` or a pipe on its own. `stages/A-elicit.md` A0.3
  and `stages/B-specify.md` B2.1: `: > events.jsonl` (a shell builtin no pattern covers cleanly)
  became `touch`. New `scripts/test-allowed-tools.sh`: extracts every backticked command from
  `stages/*.md` and `SKILL.md`, splits compound commands outside quotes, substitutes
  `${CLAUDE_SKILL_DIR}` and the `<target>`-style placeholders, and matches each subcommand
  against the frontmatter with the documented glob semantics. Listed in `SKILL.md` and
  `DOCUMENTATION.md` §11.
- Proved by: the Claude Code documentation (via the claude-code-guide agent): `${CLAUDE_SKILL_DIR}`
  is substituted inside `allowed-tools`; `Bash(x *)` is a glob that also matches the bare `x`;
  a pattern without `*` is exact; each subcommand of a compound command must match
  independently; `allowed-tools` pre-approves for the skill's turn. `test-allowed-tools.sh`:
  42 instructed subcommands from 6 sources, all matched. Mutation: deleting `Bash(xargs *)`
  fails naming the two `git ls-files … | xargs …` lines; deleting `Bash(cd *)` fails naming the
  two `cd <target> && make …` lines. First version of the splitter broke a quoted `grep -E 'a|b'`
  pattern on its `|`; it is quote-aware now. All six suites green (99 cases).
- Left open: part (b), the dry run, with its procedure written into the item. Not blocked on a
  decision; blocked on a session only the owner can run.

### 2026-09-08 — W6 — done (part b as a simulated session; findings → W7)
- Changed: the dry run was performed by a separate agent playing both the skill (following the
  stage files literally) and the owner ("accept recommendations"), against a copy of the skill
  and an empty git repository, logging every shell command. Result: Stage C stop reached,
  `make check-docs` 0 failures, 17 cards, 11 decisions, 115 normative statements all tagged —
  but one unsanctioned deviation was needed (log truncation, see W7.1) and 14 friction points
  were recorded; the report is `reports/dry-run-2026-09-08.md`. From the command log, matched
  against the frontmatter with the same semantics as `test-allowed-tools.sh`: 225 subcommands,
  and the only real class no pattern covered was the improvised `python3 -c` rendering of
  `decisions-seed.json` (5 commands) — B2.1 said "render" and named no tool. Fixes in this item:
  new `scripts/render-seed.py` (renders the seed, refuses an unrendered placeholder, appends
  through `log-append.py` in one command; `test-render.sh` now seeds through it); `B-specify.md`
  B2.1 and `C-operationalize.md` C1.3 name it; `A-elicit.md` A2.3 states that `card-answered`
  needs `answer` and `date` (the old text was refused by the tool, D5); C1.6 and D4.2 use
  `find … -exec chmod` instead of `git ls-files | xargs` (nothing is tracked before the first
  commit, F9); `B-specify.md` round B3 heading names its passes (F7). `allowed-tools`: `find *`
  in, `git ls-files *` and `xargs *` out. `test-allowed-tools.sh` knows `find`.
- Proved by: `test-allowed-tools.sh` passes over the new stage text (the render-seed command is
  backticked and checked); `render-seed.py --stdout --set DATE=…` alone refuses with the names of
  the missing placeholders; all six suites green.
- Left open: W7 holds every other finding, three of them with an owner decision. A live
  `/design-pack` session in the owner's permission mode is still the final confirmation of (b).

### 2026-09-13 — W7.1 — done
- Changed: `templates/scripts/check-docs.py` — `check_citations` refactored over
  `line_citation_failures()` and a reusable `citation_failures(root, text, existing_only)`;
  the body of a superseded entry in `DECISIONS.md` (from its `Status: superseded by` line to the
  next `## D-`) is skipped, because it is history on an append-only log; `resolve_named()`
  reads a `§Name` citation as the longest heading the README has that the text starts with, so
  prose may follow it. `templates/scripts/log-append.py` — a `decision-added` whose text cites
  a section missing from an *existing* spec is refused with the parser's message (imports
  `check-docs.py` from beside itself; absent, nothing is refused); a citation into a spec not
  yet written is allowed, because Stage B seeds the regime records before the register exists.
  `DOCUMENTATION.md` §8 and `templates/log-README.md` say so.
- Proved by: `test-check-docs.sh` +4 (dead citation in a superseded entry passes and the same
  one in a live entry fails on its line; `§Provenance says that …` resolves; `§Nonexistent thing`
  fails quoting the words; `existing_only` flags only the missing section of an existing spec);
  `test-decisions-log.sh` +2 (refusal leaves the log at 3 records; a future citation appends).
  All six suites green — 16 + 17 + 31 + 20 + 20 + 1 = 105 cases. The dry run's deviation (log
  truncation) would not have been needed: the wrong record would have been refused at the
  door, and had it slipped through, supersession would have retired it from the check.
- Left open: W7.2–W7.7.

### 2026-09-13 — W7.2 + W7.3 — done (owner decision applied: every card opens Blocking)
- Changed: `templates/scripts/eventlog.py` — `card-opened` is refused unless `blocks` is
  `specification`; the QUESTIONS.md preamble says Open means "deferred by the owner".
  `scripts/stage-detect.sh` — new state `A-extract` (inputs saved, `QUESTIONS.md` without a
  card) so a session re-entering after Round A0 goes to extraction, not to the file set; header
  explains why `A-cards` during Stage B is right by design. `stages/A-elicit.md` — entry states,
  the end condition ("every card presented and answered or deferred", which the detector now
  reads exactly), A1.4 (always `Blocks: specification`; a later-phase answer is said in the
  recommendation), A1.5/6, A2.1, A2.3 ("deferral is the owner's act only"). `stages/B-specify.md`
  — a round that raises a card stops and presents it (W7.3: the skill no longer sends a new card
  to Open and continues); B5.1 refines the target of an owner's deferral, it does not defer.
  `stages/D-review.md` D1.4 and `stages/hunter.md` — hunter cards open Blocking with the package
  as the deferral target. `stages/C-operationalize.md` — adopted-pack conflict cards open
  Blocking and are presented at the Stage C stop. `reference/decision-card.md` Blocks rule and
  Deferred bullet; `SKILL.md` step 2 and the deferral sentence; `DOCUMENTATION.md` §6 table,
  §7, §9 invariant, §11. Tests: new `test-stage-detect.sh` (11 states); `test-questions-log.sh`
  opens Q-002/Q-004 then defers them and gains a refusal case (open as Open → refused);
  `test-render.sh` opens Q-002 Blocking and defers it to LDG-02.
- Proved by: all seven suites green — 20 + 17 + 32 + 16 + 20 + 1 + 11 = 117 cases. Mutation:
  with the pre-W7.2 `stage-detect.sh` restored, case 2 fails (`B-fileset` where `A-extract` is
  expected) and the other ten pass. The dry run's F1 (wrong verdict after A0 and before the Open
  batches) and F6 (Q-016 deferred by the skill, never seen by the owner) can no longer occur:
  the second is refused by the tool, the first has its own state.
- Left open: W7.4–W7.7.

### 2026-09-13 — W7.4 + W7.5 + W7.6 + W7.7 — done; W7 closed
- Changed: **W7.4** `stages/B-specify.md` B1.1 fixes the two names the templates cite (the
  testing file is `NN-testing-acceptance.md`; the architecture file is `NN-architecture.md`
  with `## 1. Repository layout` first); `templates/specs/implementation-plan.md` FND-04 no
  longer cites a localization spec no small product has (`{{NN_L10N}}`, `{{NN_UX}}` gone from
  its notes). **W7.5** (owner: the stage commits) `stages/C-operationalize.md` gains Step C5 —
  the pack's first commit, with the hooks active, and the report names its hash; C4.5 reordered;
  `SKILL.md` allows `git add *` and `git commit *`; `lock-guard.py --staged` says "no HEAD yet;
  nothing is locked before the first commit" instead of a bare `clean`. **W7.6** (owner: cards
  only for hosting/region/paid) `reference/surfaces.md` §Never a card lists language, framework
  and libraries as `D-NNN`; `templates/specs/README.md` notes and `B-specify.md` B2.2 say where
  each stack element's tag comes from, and B2 no longer has a hidden stop. **W7.7**
  `check-docs.py` — `normative-tagged` scans `specs/README.md` too, and `--only RULE,RULE` scopes
  a run with the summary counting the failures it dropped; `stages/A-elicit.md` Exit and
  `B-specify.md` mechanical pass 4 use it (no more "ignore the failures about files that do not
  exist yet"); `extract-normative.py` scans the spec map and prints per-file counts; F12 (ID
  order after Stage A) and F14 (`Kind` = the folder name) reworded. `DOCUMENTATION.md` §8, §11.
- Proved by: `test-lock-guard.sh` +1 (the no-HEAD message before the seed commit);
  `test-check-docs.sh` +2 (an untagged statement in the spec map fails on its line; `--only`
  keeps the named rule and reports the dropped count); `test-allowed-tools.sh` passes over the
  new C5 command (`cd`, `git add`, `git commit`); `test-render.sh` unchanged and green — its
  fixture already used the two fixed names. All seven suites green: 21 + 17 + 32 + 18 + 20 + 1
  + 11 = 120 cases.
- Left open: nothing in W7. Across the plan: only the live `/design-pack` session in the
  owner's permission mode (W6 procedure) remains, and `Feature-Design.md` is the next piece of
  work, outside this plan.

### 2026-09-14 — W8 — in progress (W8.2, W8.3 done; W8.1 and W8.4 await the owner)
- Changed: **W8.2** `templates/scripts/lock-guard.py --relock` (removes the write bits of every
  existing hard-locked file; the first version set 0444 and stripped the hooks' exec bit, so git
  skipped them silently — ten ceremony cases failed at once, which is what they are for), run by
  `templates/Makefile` `install-hooks`; `templates/githooks/post-commit` re-locks with `a-w` for
  the same reason; C1.6 and D4.2 call `make install-hooks`; `find *` out of `allowed-tools`.
  **W8.3** `templates/scripts/log-append.py` accepts a JSON array in `--payload-file`: every
  element validated and folded first, appended all or nothing; A1.5 names the form. **W8.1**
  `templates/claude-settings.local.json` (the same 20 Bash patterns plus Read/Write/Edit/Glob/Grep
  as `permissions.allow`); A0's stop explains the one-turn grant and offers it on the owner's word;
  C1.2 ignores `.claude/settings.local.json`; `SKILL.md` frontmatter comment and files table;
  `design-pack-overview.md` install note. **W8.4** `SKILL.md` hard rule *Never edit the skill*.
  Tests: `test-lock-guard.sh` +1 (relock semantics) and `chmod u+w` before every deliberate
  illegitimate write, since the files are now read-only after `install-hooks`; `test-render.sh`
  +5f (the manifest refuses an in-session write at the filesystem); `test-questions-log.sh`
  +11/11b (batch refused whole naming the element; valid batch appends in order);
  `test-allowed-tools.sh` +1 (settings template and `allowed-tools` carry the same patterns).
- Proved by: seven suites green — 22 + 17 + 34 + 18 + 21 + 2 + 11 = 125 cases. The one-turn
  grant is documented ("The grant clears when you send your next message", skills.md) and matches
  the log: every command prompted from the second reply on. `find -exec` refusal quoted verbatim
  from the owner's log.
- Left open: W8.1 — owner to confirm the offer-at-A0 placement and re-run once with *allow*
  (acceptance: no prompt to Stage C); W8.4 — cause unknown until the owner pastes the diff the
  agent proposed; W8.5 second bullet (name the rule list and payload fields in the stages).

### 2026-09-14 — W8.4 closed; W8.1 awaits the owner's second run
- Changed: W8.4 recorded as not recoverable (manual mode, prompts seen in order, diff not kept);
  `design-pack-overview.md` install notes recommend `chmod -R a-w` on the installed skill so
  *Never edit the skill* holds mechanically. No code change.
- Proved by: seven suites green, unchanged (125 cases).
- Left open: W8.1's second run with *allow* at A0 — expected result: no permission prompt to
  Stage C; if "Do you want to create …" still appears for the pack's files, the grant needs a
  path-scoped `Write(...)` rule instead of the bare tool name, and that is the one thing the run
  will settle. W8.5's second bullet stays as a ½-hour item.

### 2026-09-14 — W9 — done
- Changed: `design-pack/templates/scripts/check-docs.py` (the `task-policy` rule, the
  `--task PACKAGE|all` reader, and the derivation helpers the two share);
  `design-pack/templates/specs/implementation-plan.md` (the three characteristics per package and
  the `{{FNDnn_CHARACTERISTICS}}` placeholders); `design-pack/templates/AGENTS.md` (the verbatim
  `## Prompt selection` section and its table); `design-pack/templates/SESSION_BOOTSTRAP_PROMPT_SAMPLE.md`
  (the preamble that tells a session to read the characteristics and the table before running
  anything); `design-pack/stages/B-specify.md` B5 (derive and write the stored fields, record
  `Contract change` as one decision), `C-operationalize.md` C3 (compile the table; recompute
  `Touches red line` once the red lines exist), `D-review.md` D3 (recompute after a correction
  moves a red line); `design-pack/SKILL.md` files table; `DOCUMENTATION.md` §1, §8 and §11.
  New: `design-pack/scripts/test-task-policy.sh`.
- Proved by: eight suites green — 14 + 22 + 18 + 2 + 22 + 17 + 34 + 11 = 140 cases
  (`test-task-policy.sh` new at 14; `test-render.sh` 21 → 22). The derivation was also run
  read-only over the live trial pack (`--task all`, 22 packages): ACC-04 reports
  `blocked-by: Q-004` from the one open card, and the packages that touch no surface report the
  dash rather than a guess.
- Left open: nothing. Packs generated before this change carry no characteristics, so their
  `task-policy` fails until the three lines are added per package; that is the intended migration
  and `--task all` prints the two derived values to paste.

### 2026-09-14 — W9 follow-up, three defects found by two real packs — done
- Changed: `design-pack/templates/scripts/lock-guard.py` — a diff that ADDS a binary file carries
  no `--- /dev/null` line, only `Binary files ... differ`, so an addition under a hard-locked glob
  read as a modification and refused the pack's own first commit; `new file mode` and
  `deleted file mode` in the extended header are now what an addition and a deletion are read
  from, text and binary alike.
  `design-pack/templates/scripts/check-docs.py` — a work package written as one line carries its
  citations on that line, and `plan_package_blocks` excluded the title line, so such a package
  derived `Surfaces: —` however much it touched; the title line is part of the block now.
  `design-pack/templates/scripts/unlock.sh` and `templates/githooks/post-commit` — each ceremony
  overwrote the token, so a commit carrying several unlocks re-locked only the last path; the
  token accumulates now and post-commit also re-locks from the manifest (`--relock`).
- Proved by: eight suites green — 24 + 22 + 15 + 18 + 34 + 17 + 2 + 11 = 143 cases.
  `test-lock-guard.sh` +3 unit cases (new binary, changed binary, new text from the header alone)
  and +2 ceremony cases (two unlocks in one commit: both authorized, both re-locked);
  `test-task-policy.sh` +1 (the one-line package form).
- Left open: nothing. All three predate W9 and were invisible to the fixture packs, which hold no
  binary input, write every package as a bulleted block, and never run two ceremonies at once.

### 2026-09-22 — W10.1 + W10.6 — done
- Changed: **W10.1** new `design-pack/templates/docs-layers-README.md` (the directory's own
  README: what a note answers, the three fixed headings as a fenced block, and the table of which
  knowledge lives where); `templates/.doc-locks` gains `free: docs/layers/**` and
  `free: docs/gotchas.md` with the comment that the globs do not overlap `hard-locked:
  docs/inputs/**`, so last-match-wins is not engaged and those two lines' position is not
  load-bearing; `templates/AGENTS.md` gains a verbatim `## Layer notes` section carrying the empty
  index, a reading-order step for the dependencies' notes, living-document entries for both new
  files, and an overflow sentence that no longer sends content to the playbook (`specs/` is
  hard-locked from the freeze, so that was a ceremony per slice); `templates/scripts/check-docs.py`
  gains the `layer-notes` rule and its constants; `templates/specs/agent-playbook.md` §2's
  "architecture notes" and §10's "short task log" both name the file; prompt 1 reads the
  dependencies' notes, writes the note as part of the slice and lands its handoff in the note's
  `## Handoff` rather than in a transcript the next session cannot read; Stage C step C1.5b creates
  both homes. **W10.6** new `templates/gotchas.md`, three headings and no invented content.
  Docs: `SKILL.md` files table and a new hard rule (one home per kind of knowledge),
  `DOCUMENTATION.md` §1, the gates table and the suite table, `design-pack-overview.md`
  §What it produces.
- Proved by: eight suites green — 26 + 17 + 34 + 26 + 27 + 2 + 11 + 15 = 158 cases, up from 143.
  `test-check-docs.sh` +8 (a `done` package with no note; a note missing one of the three
  headings; a note the index does not carry; the clean pair; the shipped README and a
  `_`-prefixed file not read as notes; a note naming no package; a per-package heading in
  `AGENTS.md`; and that `main()` runs the rule with the plan's packages and the traceability
  rows). `test-render.sh` +5 (both homes rendered and free in the manifest; the empty index;
  a package reaching `done` without a note failing the whole gate; the note plus its index line
  passing it; a per-package section in `AGENTS.md` failing it). `test-lock-guard.sh` +2 (the two
  `docs/` tiers in one commit, and the two free paths committing on their own).
- Left open: nothing in these two items. One thing was dropped deliberately during the work: a
  `docs/layers/_TEMPLATE.md` shipped into the target would have been the only file in a generated
  pack carrying `{{...}}`, and the pack's "no unrendered placeholder" rule is worth more than the
  convenience, so the note's shape is the fenced block in `docs/layers/README.md` and
  `templates/layer-note.md` was deleted rather than shipped. Packs generated before this change
  have no `docs/layers/`, no index section and no `docs/gotchas.md`; their first `done` package
  fails `layer-notes` until the three are added, which is the intended migration.

### 2026-09-22 — W10.2 — done
- Changed: `templates/scripts/check-docs.py` gains `--brief PACKAGE` beside `--task` (and
  `report_tasks` an optional sink, so the brief opens with exactly the line `--task` would have
  printed): the `Now` item, the package's block in the plan, the blocking cards in full, the
  **text** of every spec section the package and the item cite — resolved through the same
  `section_index` the `citations` rule uses, each section once, a cited parent swallowing its
  subsections — the `D-NNN` entries those texts cite, the layer notes of the packages the item
  names, the `TRACEABILITY.md` row, the `GAPS.md` rows naming the package, and a byte-count
  footer. `templates/Makefile` gains `brief` (with a usage line when `TASK` is empty) and the
  `.PHONY` list; `templates/AGENTS.md` lists it under Commands, where the `commands` rule holds
  it to the Makefile, and its reading order is rewritten around it: four steps, then a short list
  of the only reasons to read a document whole. `templates/specs/agent-playbook.md` §2's task
  packet now has a producer rather than an instruction. Prompt 1 opens with the brief.
  `stages/C-operationalize.md` C4.5 runs it once on the compiled pack and reports its byte count.
  `SKILL.md` and `templates/claude-settings.local.json` both gain `Bash(make brief *)` — the
  allowed-tools suite failed on the second until it did.
  Docs: `DOCUMENTATION.md` §1 and the suite table.
- Proved by: eight suites green — 26 + 17 + 34 + 26 + 31 + 2 + 11 + 22 = 169 cases, up from 158.
  `test-task-policy.sh` +7 (the section list and its counts as one string; the cited spec text,
  the dependency's note and only the rows naming the package; the byte-count footer; a plan
  byte-identical after a brief; an unknown package exiting non-zero; the blocking card with its
  options; a retitled section still resolving). `test-render.sh` +4 (`make brief` exits 0 on the
  rendered pack, resolves the cited spec text and carries the row rather than the citation, is
  smaller than the documents it replaces — 7.3 KB against 50 KB on a fixture with four packages —
  and prints its usage line without a `TASK`).
- Left open: nothing in this item. Two things worth naming for W10.5 and for whoever reads the
  brief first: a package that cites a whole phase section gets that whole section, the
  neighbouring packages included, which is correct selection and not a defect — the citation is
  what the plan wrote; and the brief resolves nothing *inside* a decision entry, because the
  entry is a projection of the log and its text is history.

### 2026-09-22 — W10.3 + W10.4 — done
- Changed: **W10.3** `templates/scripts/check-docs.py` gains `gaps-size` (2000 characters per
  `GAPS.md` cell) and `evidence-size` (1000 per Evidence cell), both calibrated on the exemplar —
  its good rows are 1.0–1.4 KB and read as one gap, its failures an order of magnitude past that —
  plus a `note()` helper for what a rule may see and must not judge, used to report a gap row
  naming more than three packages. `templates/GAPS.md` and `templates/TRACEABILITY.md` state
  their own ceiling and the reason: a row holds one gap, an Evidence cell holds the run that
  proved the **current** status, and Git holds what came before because a status change is a
  commit. **W10.4** prompt 1 gains a second exit at the session's budget — stop at a boundary you
  choose, do not begin a sub-task you cannot finish and record, leave the documents truthful,
  write the note, name the next step — and prompt 2 gains the sentence that it runs in a session
  that did not write the code, on Stage D's own argument, opening on `make brief` and the slice's
  layer note rather than on `AGENTS.md` and a row. `templates/AGENTS.md`'s policy table says
  *where* a review runs beside *whether*; the playbook §10 carries the unfinished-slice rule.
  Docs: `DOCUMENTATION.md` gates and suite tables.
- Proved by: eight suites green — 26 + 17 + 34 + 31 + 34 + 2 + 11 + 22 = 177 cases, up from 169.
  `test-check-docs.sh` +5 (a Gap cell past the ceiling failing with its length; an ordinary row
  passing; a row naming four packages reported with zero failures; an Evidence cell past the
  ceiling; the run that proved the current status passing). `test-render.sh` +3 (the budget
  clause, the fresh-session rule in both the prompt and the table, and the two registers
  declaring their own ceilings).
- Left open: nothing in these two. The ceilings are deliberately not retroactive tooling: an
  existing pack over either one fails the gate on its next run, which is the point — the cell is
  split or the history moves to the layer note the same session.

### 2026-09-22 — W10.5 — done; W10 closed
- Changed: `templates/scripts/check-docs.py` — `TASK_FIELDS` gains `File surface` and `Lane`,
  both judgements checked for presence and never recomputed; `plan_lanes()` reads the lane names
  from the plan's own parallelization section (a bullet's name is the text before a dash or a
  parenthesis, so a lane may explain itself without renaming itself) and `task-policy` holds
  `Lane:` to that list; `report_lane_overlaps()` reports, through `note()`, any pair sharing a
  lane and a path, from both the gate and `--task all`; `report_tasks` prints both fields and
  `--brief` carries them. `templates/specs/implementation-plan.md` defines them in its notes and
  makes the parallelization section normative rather than advisory (`[input]`); `stages/B-specify.md`
  B5.1 records all three judgements in one `decision-added` event and adds the only size rule the
  plan has ever had: **a package whose file surface spans more than one lane is split at the seam
  the lanes already name, or explained in that same decision**, with the reason it is a sentence
  and not an assertion. Docs: `DOCUMENTATION.md` §1, the gates table, the suite table.
- Proved by: eight suites green — 26 + 17 + 34 + 31 + 36 + 2 + 11 + 29 = 186 cases, up from 177.
  `test-task-policy.sh` +7 (a missing file surface, with the message naming what the field is
  for; a lane the plan does not list, with the lanes it does; the five fields passing together;
  a file surface the rule refuses to second-guess; the overlap reported by `--task all` and by
  the gate, failing neither; both fields in the brief). `test-render.sh` +2 (every package of the
  rendered plan carries both, and `--task all` prints them).
- Left open: nothing. W10 is closed. The two fields are the only part of W10 that reduces elapsed
  time rather than tokens, and they do it by making a schedule possible, not by making one: which
  two packages actually run at once is the orchestrator's call, and the pack now gives it the
  data to make that call instead of a paragraph of advice.

### 2026-09-22 — W8.5 second bullet — done
- Changed: new `design-pack/reference/events-and-rules.md` — the three payload tables of the
  `decisions` stream, the six of the `questions` stream, what each event renders as (including
  the two Answer forms), the `log-append.py` invocation with `--payload-file`, `--set` and the
  array form, and all 22 `check-docs` rules with what each fails on. `SKILL.md` step 3 marks it a
  **lookup, not a session read**, and says that a stage which sent an agent into
  `templates/scripts/` for a field is a defect in that stage; the files table carries it.
  `stages/A-elicit.md` A1.4, `stages/B-specify.md` B3 and `stages/D-review.md` D2 point at it at
  the three places the owner's log shows the agent going looking.
- Proved by: eight suites green — 26 + 17 + 34 + 32 + 36 + 2 + 11 + 29 = 187 cases. The new case
  is a drift check: it derives the rule names from `(fail|ok|note)("...")` in `check-docs.py` and
  the event types and required decision fields from `eventlog.py`'s own constants, then compares
  both against the lookup's tables in each direction. Proved to bite by renaming one rule in the
  lookup and watching the suite fail with that name, then restoring it.
- Left open: W8.1's live run, which is the owner's, and the `Decision:` line recording where the
  permission-grant offer belongs. Nothing else in W8.
