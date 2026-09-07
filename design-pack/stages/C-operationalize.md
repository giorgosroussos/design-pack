# Stage C — Operationalize

Entry: `stage-detect` said `C`. The spec pack is complete and its mechanical pass is clean
except for checks that need the root documents.

Stage C generates the operating layer and the living documents. It has one round and stops
once at the end. Everything here is compiled from the pack; nothing new is decided. If
compiling exposes a missing decision, it is a card (Blocking → stop and present it) or a
`D-NNN`, never an improvised sentence in `AGENTS.md`.

## Adopted packs

A pack enters Stage C without Stages A and B when `docs/inputs/README.md` declares an existing
`specs/` directory an authoritative input in itself (the owner froze it elsewhere and adopts it
as-is). Its statements are `[input]` by declaration. Before Step C1:

1. Append ` [input]` to every untagged bullet of the locked register, above its change-control
   section. This is the only edit to a domain statement the skill makes without a card.
2. If `specs/README.md` has no `## Provenance` section, append the one from
   `templates/specs/README.md` after Requirement language. Named sections; nothing renumbered.
3. Use `--untagged-as input` on every `extract-normative` run for this pack (Stage D too), so
   the hunter and the input auditor see the adopted statements as owner-stated. The input
   auditor then verifies them against `docs/inputs/`, which for an adopted pack is the pack
   itself, so it will report nothing; say so in the report rather than skipping the agent.
4. Stage A did not run, so append the `card-opened` events Stage A would have appended, one for
   every behavioural conflict that `docs/inputs/README.md` records between a non-authoritative
   input and the pack (`reference/decision-card.md` shape; `blocks` names the work package the
   conflict affects, never `specification`, so they render Open), then rebuild the projection. If a compiled red line or design-direction sentence would otherwise name a
   conflict with no card, this is where the card comes from.

## Step C1 — Verbatim assets

1. Copy `${CLAUDE_SKILL_DIR}/templates/scripts/check-docs.py` to `<target>/scripts/check-docs.py`
   unchanged; `chmod +x`.
2. Copy the lock layer, all unchanged: `templates/scripts/lock-guard.py` and
   `templates/scripts/unlock.sh` to `<target>/scripts/`; `templates/.doc-locks` to the target
   root; `templates/githooks/pre-commit`, `post-commit`, `pre-receive` and `README.md` to
   `<target>/.githooks/`. `chmod +x` the two scripts and the three hooks. Render
   `templates/UNLOCKS.md` (no placeholders; strip the notes block). Add `.doc-unlock` to
   `<target>/.gitignore`, creating that file if it does not exist: the unlock token is local
   and single-use and is never committed.
3. Copy the log tooling, all unchanged: `templates/scripts/eventlog.py`, `log-append.py`,
   `rebuild-decisions.py`, `rebuild-questions.py` and `verify-chain.py` to `<target>/scripts/`;
   `chmod +x` the four tools. `eventlog.py` is a module rather than a tool: the three tools and `check-docs.py`
   import it, so it has to sit beside them. Render `templates/log-README.md` into
   `<target>/.log/README.md`. If the target has no `.log/events.jsonl` — an adopted pack that
   never ran Stage B — create it empty and seed the four regime records exactly as
   `stages/B-specify.md` round B2 does, then rebuild the projection.
4. Render `Makefile` from its template (product name; keep or drop the contract-drift target).
5. Render `CLAUDE.md`, `SESSION_BOOTSTRAP_PROMPT_SAMPLE.md` and `README.md` from their
   templates. Placeholders only; no new rules.
6. Activate the layer, when the target is a git repository:
   `cd <target> && make install-hooks` (which is `git config core.hooksPath .githooks` plus the
   exec bits), then make the hard-locked files read-only:
   `git ls-files -z docs/inputs | xargs -0 -r chmod 0444`. An accidental in-session overwrite
   then fails at the filesystem before it ever reaches a commit. Git records only the exec bit,
   so the mode is local to the clone and `make install-hooks` runs again after every clone; the
   hooks, not the mode bits, are the guarantee. If the target is not a git repository, say so in
   the report and leave the hooks uninstalled rather than initializing one. Never `chmod`
   `DECISIONS.md` or `.log/events.jsonl`: the first has to stay writable for the rebuild, the
   second for the append. The manifest keeps them `free` and `append-only` for that reason.
7. Do not change a tier in `.doc-locks`. The manifest ships with `specs/` and `QUESTIONS.md`
   free, because Stage D still rewrites spec statements and still moves cards between sections;
   the freeze promotes them (`stages/D-review.md` Round D4).

## Step C2 — Living documents in truthful-empty state

1. `PLAN.md`: Now = FND-01 as the template writes it; Next = the remaining Phase 0 packages,
   one line each, from the plan.
2. `GAPS.md`: G-001 only, unless an Open card names a gap the owner chose to carry (then a row
   citing the card's package).
3. `TRACEABILITY.md`: one row per package in plan order, one per critical journey from the
   testing spec; every status `not started`, every evidence `—`. Nothing else is ever written
   here by the skill.
4. `QUESTIONS.md`: do not edit it. Run `python3 scripts/rebuild-questions.py`; the sections, the
   index and the "None. Phase 0 can proceed." line under an empty `## Blocking` are all generated.
   A card that looks misplaced is an event that is missing, not a line to move.
5. `DECISIONS.md`: do not edit it. Run `python3 scripts/rebuild-decisions.py` and confirm the
   projection carries D-001 to D-004 and an index line for each. The index is generated with the
   entries, so a missing line means a missing event, not a missing line.

## Step C3 — Compile `AGENTS.md`

Render from the template. For each compiled placeholder:

- **Product paragraph.** From the spec map's product statement and the scope file's actors and
  success criterion, with citations. No adjective the specs do not use.
- **Non-authoritative paragraph.** From `docs/inputs/README.md` and D-003.
- **Red lines.** Candidates are: every register bullet; every `MUST NOT` in the security file;
  the excluded-capability list; identifier and secret rules; testing-honesty rules (real
  database, no weakened tests); database-change rules. Merge them into 8–12 bullets, each a
  compression with a bold title and its citations in parentheses. Every bullet contains a `§`.
  A red line that cites nothing is a sign the spec lacks the statement. For a pack this skill
  wrote, add the statement to the spec with its tag (a card if it touches a surface, else a
  `D-NNN`) before writing the red line. For an adopted pack, do not write the red line; if
  the missing statement touches a surface, it is a card.
- **Architecture and stack.** The technology baseline as prose, the layout block from the
  architecture file, topology and storage, ending with the sentence about tooling the specs
  leave open being chosen in `DECISIONS.md`.
- **Commands.** The template's list. Keep or drop the drift target consistently with the Makefile.
- **Design direction.** Only when a visual input exists: the principles to carry, and the card
  IDs that hold each conflict.

Then check the size. Above 20 KB, compress the red lines and the topology paragraph; move
nothing into `CLAUDE.md`.

## Step C4 — Mechanical pass

1. `cd <target> && make check-docs` must exit 0. Fix living documents and `AGENTS.md`; if a fix
   needs a spec statement, add it with its tag (the pack is not frozen yet).
2. `grep -rn '{{' <target> --include='*.md' --include=Makefile` finds nothing.
3. `grep -rniE 'design-pack|template notes|CLAUDE_SKILL_DIR' <target>` finds nothing outside
   `docs/inputs/`. The copied `scripts/check-docs.py` mentions `{{` in its own documentation;
   that is why step 2 is limited to markdown and the Makefile.
4. The log answers: `make verify-chain` exits 0, `make check-docs` reports `chain-intact` and
   `projection-fresh` passing for both `DECISIONS.md` and `QUESTIONS.md`, and running each
   `rebuild-*` tool twice leaves its file unchanged the second time. If the rebuild is not byte-stable, `projection-fresh` will
   fail on a clean repository and the cause is the renderer, not the pack.
5. The lock layer answers: `make check-locks` exits 0 with nothing staged,
   `git config core.hooksPath` reads `.githooks`, and
   `python3 scripts/lock-guard.py --tier docs/inputs/README.md` prints `hard-locked` while
   `--tier PLAN.md` prints `free`. A manifest that fails to parse exits 2 and is a Stage C
   failure, not a warning.

## Exit

Report: files generated with sizes, `AGENTS.md` size against the ceiling, red-line count,
`check-docs` result, and the lock layer: hooks active or not, how many files were set read-only,
and the tier of each locked path. State that Stage D runs the assumption hunter and then asks the owner to
read the pack. Stop.
