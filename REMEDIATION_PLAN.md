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
| W7 | Findings of the dry run (F1–F14, D1–D5) | mixed; 3 owner decisions | ~2 days | not started |

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

Status: not started
Decision: three of the items below are the owner's (marked **owner**); the rest are fixes.

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
- [ ] a superseded entry with a dead citation passes `citations`; a live entry with one fails.
- [ ] `` `specs/README.md` §Provenance says that… `` resolves; `§Nonexistent` fails.
- [ ] `log-append` refuses a `decision-added` whose text cites a section that does not exist.

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
