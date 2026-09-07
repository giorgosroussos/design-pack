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
- Run all three existing suites before closing any item; a regression anywhere reopens the
  item that caused it.

```
bash design-pack/scripts/test-lock-guard.sh
bash design-pack/scripts/test-decisions-log.sh
bash design-pack/scripts/test-questions-log.sh
bash design-pack/scripts/test-check-docs.sh
```

## Summary board

| # | Item | Category | Est. | Status |
| --- | --- | --- | --- | --- |
| W1 | Mechanical bugs (A1–A8) | A — local fixes | ½ day | done |
| W2 | Render-and-check acceptance suite | D — safety net | ½ day | not started |
| W3 | Manifest demotion guard + self-protection | B — enforcement | 1 day | not started |
| W4 | `normative-tagged` and `inferred-zero` rules | C — enforcement of the core claim | ½ day | not started |
| W5 | Honest limits: unlock record is an audit trail | docs | ½ hour | not started |
| W6 | `allowed-tools` completeness + real dry run | B — usability | ½ hour + a run | not started |

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

Status: not started
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
- [ ] suite exists and passes on the current templates.
- [ ] deliberately breaking one template (e.g. a red line without `§`) makes it fail.
- [ ] added to `SKILL.md` "Files in this skill" and to `DOCUMENTATION.md` §11.

---

## W3 — The manifest can demote its own locks

Status: not started
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

- [ ] test: appending a demotion + editing the demoted path in one commit is blocked locally.
- [ ] test: push 1 (demotion only) is **rejected** by the pre-receive simulation.
- [ ] test: appending `hard-locked: specs/**` (a promotion) is accepted with no ceremony —
      when `.doc-locks` is still append-only in the fixture; and requires `make unlock` once
      the Stage-C manifest makes it hard-locked. Both fixtures covered.
- [ ] test: editing `scripts/lock-guard.py` without `make unlock` is blocked.
- [ ] `stages/D-review.md` D4 updated: the freeze runs `make unlock PATH=.doc-locks REASON=...`
      before appending the promotion.
- [ ] `stages/C-operationalize.md` C1.2 and C1.7, `templates/.doc-locks` comments,
      `templates/githooks/README.md`, `DOCUMENTATION.md` §5.1–5.2 updated.
- [ ] W2 suite still passes.

---

## W4 — The core claim is not mechanically enforced

Status: not started
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
prevent. Decision: ________

### Acceptance

- [ ] an untagged `MUST` in a domain file fails `normative-tagged`; the same line in a fenced
      block or in backticks does not.
- [ ] lead-in inheritance: `The MVP MUST: [input]` followed by untagged items passes.
- [ ] `[inferred]` in a `Status: Draft` pack passes; the same pack stamped
      `Status: Implementation baseline` fails `inferred-zero`.
- [ ] `extract-normative.py` output is byte-identical before and after the refactor on the W2
      fixture.
- [ ] `design-pack-overview.md`, `DOCUMENTATION.md` §8 gates table, `SKILL.md` rule list,
      `stages/D-review.md` D2 updated (D2 step 2 becomes "check-docs passes", not a manual read).
- [ ] W2 suite passes.

---

## W5 — Honest limits: the unlock record is an audit trail, not authorization

Status: not started
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
- [ ] `grep -rn "guarantee" DOCUMENTATION.md design-pack/` — every remaining use is accurate.
- [ ] W2 leakage greps unaffected.

---

## W6 — `allowed-tools` does not cover the commands the stages instruct

Status: not started
Decision: none needed; verify `${CLAUDE_SKILL_DIR}` interpolation empirically before choosing
the pattern form.

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

Acceptance:
- [ ] dry run reaches the Stage C stop with zero unexpected permission prompts.
- [ ] every command in `stages/*.md` has a matching pattern (re-run the grep from the review:
      `grep -rhoE '\b(make [a-z-]+|git [a-z-]+|mkdir|chmod|xargs|grep -)' design-pack/stages design-pack/SKILL.md | sort -u`).

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
