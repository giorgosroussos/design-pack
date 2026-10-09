# design-pack — what the skill is and how it works

`design-pack` turns raw requirements plus owner decisions into a repository-ready documentation
pack that a GenAI implementation agent can work from without ever talking to the person who
wrote the requirements again.

It is invoked manually: `/design-pack [target-dir]`. It converses in the owner's language and
writes every generated file in English. The generated repository never mentions the skill.

- Installed, the skill lives in `~/.claude/skills/design-pack/`.
- Its source is this repository's `design-pack/` directory; the core mechanisms it generalizes
  from the exemplar are under `design-pack/reference/`.

---

## 1. What it produces

```
AGENTS.md              entry point; the only file the implementation agent must read first
CLAUDE.md              thin pointer to AGENTS.md
README.md              the product's own readme
Makefile               the command contract; the gates below are real from the first commit
specs/                 the contract: numbered domain files + traceability, decision register,
                       implementation plan, agent playbook
PLAN.md                Now and Next only
GAPS.md                deliberate incompleteness, closed only by evidence
TRACEABILITY.md        status and evidence per work package and per critical journey
DECISIONS.md           projection of the log's `decisions` stream
QUESTIONS.md           projection of the log's `questions` stream
UNLOCKS.md             one line per ceremonial unlock of a locked file
.log/events.jsonl      the append-only, hash-chained event log: the source of truth
.log/README.md         the log's canonical form, and what its chain does not guarantee
.doc-locks             which paths are hard-locked, append-only or free
.githooks/             pre-commit, post-commit and the pre-receive mirror
scripts/               check-docs, lock-guard, the log tools, unlock
docs/inputs/           the raw material, verbatim, with an authority README
docs/layers/           one note per delivered work package: what it established, what a later
                       slice must not do, and that session's handoff; AGENTS.md indexes them
docs/gotchas.md        what the tooling does that an agent cannot predict, empty until it costs
                       a session to learn
SESSION_BOOTSTRAP_PROMPT_SAMPLE.md   the loop prompts an implementation session starts from, and
                       1o, the one a session under an orchestrator starts from
```

Three document layers with one rule between them: `specs/` is the frozen contract, `AGENTS.md`
is the operating layer that compiles it, and the root documents are the living state. Nothing is
repeated between them; they cite each other.

A fourth home exists for what implementation itself produces. What a delivered package
established — the names a later slice calls, the alternatives this layer has already closed —
is neither contract nor state, and it has one destination: `docs/layers/<PACKAGE>.md`, written
by the session that delivers the package and carrying that session's handoff. `AGENTS.md` holds
one index line per note and never the content, so the entry point stays readable while the
knowledge grows, and a session reads only the notes its dependencies name. `layer-notes` enforces
both halves: a `done` package owes a note, and no heading in `AGENTS.md` may name a package. The
rule exists because the alternative was measured: in the pre-skill exemplar this method was
generalised from, 186 of that repository's 209 KB entry point were thirty-one sections, one per
work package, read in full by every session forever.

The same separation decides which of the session prompts a task gets. The plan states DATA:
every work package carries `Surfaces`, `Touches red line`, `Contract change`, `File surface`,
`Lane` and `Depends on` — the first two derived from the sections it cites and verified by
`check-docs`, the next three the plan author's recorded judgements, checked for presence and shape
and never recomputed, and the sixth the author's apart from one derived pair: a package citing a
section that a `Contract change: yes` package of its phase also cites depends on it.
`File surface` is what the playbook's task packet means by "files it may change"; `Lane` is one of
the lanes the plan's own parallelization section lists, so two packages in different lanes can run
beside each other and `--task all` reports any pair that shares a lane and a path. Without them a
plan has no size and no schedule: nothing at Stage B notices a package three subsystems wide, and
nothing can tell an orchestrator which two packages are safe at once. `AGENTS.md` states POLICY: one table mapping those characteristics to the
prompts to run. So the contract never says "run a review here", it says "this package touches
security", and the table — in the free tier, tunable without unlocking `specs/` — says what that
implies. The fourth characteristic, `blocked-by`, is never stored: it is read from `QUESTIONS.md`
when the task starts, so resolving a blocking card needs no ceremonial unlock of a hard-locked
plan.

The same reasoning decides what a session reads. Which parts of the pack a task needs is a
derivation over citations the pack already carries, so it belongs in a command rather than in an
agent's judgement: `make brief TASK=<PACKAGE>` prints the package's characteristics, the `Now`
item, its block in the plan, the cards blocking it, the **text** of every spec section it cites,
the decisions those cite, the layer notes of the packages it names, its `TRACEABILITY.md` row and
the `GAPS.md` rows naming it — then its own byte count, which is that package's reading cost. It
selects and never summarises: every line it prints is a line of the pack, so it cannot become a
second source of truth. The session prompt opens with it and names no document whole except
`AGENTS.md` and the two short files that govern everything the brief contains.

---

## 2. The three layers of the design

The pack answers three separate questions, and each has its own machinery.

| Layer | Question | Mechanism |
| --- | --- | --- |
| **Decision regime** | who decides what, and is it written down | five surfaces, decision cards, provenance tags, the assumption hunter |
| **Record** | can the history be trusted later | an append-only hash-chained event log, with the markdown as a regenerated projection |
| **Enforcement** | is any of it actually guaranteed | a lock manifest, a diff guard, git hooks, a ceremonial unlock |

They compose in one direction: the regime decides what gets written, the log makes the writing
immutable and auditable, the enforcement layer makes both mechanical rather than remembered.

---

## 3. Layer one — the decision regime

The quality of a spec pack is decided by **which decisions the owner makes and which the agent
makes**. An answer the agent gives itself, however reasonable, becomes a locked constraint
nobody questions again.

### 3.1 The five surfaces

A question belongs to the owner if and only if its plausible answers change one of:

| Surface | What changes it |
| --- | --- |
| data | entities, relationships, identifiers, what is stored, for how long |
| security | who accesses what, authentication, the ownership or tenancy boundary, trust boundaries |
| scope | what is MVP, what is Future, what is excluded |
| external | money, third parties, jurisdiction, legal obligations, mandated retention |
| ux | primary navigation, critical journeys, brand behaviour |

Everything else the agent decides itself and records with its alternatives. Two traps the filter
names explicitly: a tooling choice that leaks into a surface is the owner's (map *library* is
tooling, map *tile provider* is external), and a default being reasonable is not a reason to
decide it silently.

### 3.2 The decision card

The only shape a question to the owner may take. If "effect on surface" cannot be filled for at
least one option, it is not the owner's question. If it can, it must be asked. There is no third
category: every candidate ends as a card in the `questions` stream or a decision in the
`decisions` stream.

### 3.3 Provenance on every normative statement

Every `MUST`, `SHOULD` and `MAY` in `specs/` ends with a tag saying who decided it. The locked
register may hold only owner provenance, and `check-docs` enforces that mechanically.

### 3.4 The assumption hunter

At Stage D a fresh agent with no conversation context reads the pack and writes every
surface-touching statement that is not owner-decided as a card. It fixes nothing and judges
nothing. A second agent audits every `[input]` tag against the raw inputs. Both run until they
return zero findings.

---

## 4. Layer two — the record: one log, two projections

`DECISIONS.md` and `QUESTIONS.md` are **not** authored. They are rendered from
`.log/events.jsonl`, which is the source of truth.

The reason is narrow and concrete. Append-only protection stops a line from being deleted, but a
changed body under an unchanged ID is invisible to any check that reads only the current state.
And "which decisions are live, which are superseded" was reconstructed by a human reading down an
ever-growing file. A log fixes both: history becomes immutable and tamper-evident, and current
state becomes a function of it.

### 4.1 The record format

One JSON object per line, keys in a fixed order:

| Field | Meaning |
| --- | --- |
| `seq` | 1-based, contiguous across the whole file. A gap is a break. |
| `ts` | ISO-8601 UTC |
| `actor` | `agent` or `owner` |
| `stream` | `decisions` or `questions` |
| `type` | event type within the stream |
| `payload` | exactly the fields the projection renders |
| `prev` | sha256 of the previous record's canonical form, 64 zeros at `seq` 1 |
| `hash` | sha256 of this record's canonical form |

**Canonical form**, the rule everything depends on: take the record without its `hash`,
serialize it as JSON with sorted keys and no insignificant whitespace, UTF-8, concatenate the
literal `prev`, sha256 the result. Hashes are computed over the record, never over the bytes of
the line, so a line can be reformatted without invalidating anything and verification does not
depend on the file's whitespace. `scripts/eventlog.py` is the single implementation of it.

### 4.2 The two streams

| Stream | Events | Projection |
| --- | --- | --- |
| `decisions` | `decision-added`, `decision-superseded`, `adr-approval-changed` | `DECISIONS.md` |
| `questions` | `card-opened`, `card-answered`, `card-deferred`, `card-reactivated`, `card-resolved`, `card-superseded` | `QUESTIONS.md` |

Both share one file and one sequence, told apart by `stream`. Each projection folds only its own
records and reads only `type` and `payload`, so interleaving is irrelevant to what it renders: a
log of `dec, q, dec, q` renders byte-for-byte the same two files as two separated logs of the
same events. `verify-chain` walks the whole file in one pass, regardless of stream.

The consequence worth naming: a card no longer *moves* between the Blocking, Open and Resolved
sections. It moves because `card-deferred`, `card-reactivated` or `card-resolved` says so, which
turns a diff nobody could audit into history.

### 4.3 The supersession seam

When the owner changes their mind, the new card carries the spec statement's `[Q-NNN]` tag and
the old card gets a `card-superseded` event. The old card stays Resolved and keeps its answer and
its options, because the options the owner saw are the only record of why the decision reads as
it does.

That used to break the `provenance` rule: a Resolved card that nothing cites. Now the rule exempts
a superseded card and instead requires that its successor exists. The exemption is only safe
because supersession is an event rather than a hand edit — nobody can claim it after the fact.

### 4.4 What the chain guarantees, and what it does not

**It guarantees** that any change to a record already in the log is detectable: the record's own
hash stops matching and so does every later `prev`, and `make verify-chain` names the first
broken link. Removing a line is caught earlier, by the append-only tier in `.doc-locks`.

**It does not guarantee authorship.** Anyone who can run the tooling can write a well-formed new
record, or rewrite the chain from a chosen point and recompute everything after it. The threat
model is an agent editing history by accident and a silent rewrite passing unnoticed in review,
not a motivated adversary. Signing, or keeping the head hash outside the repository, would be a
different mechanism. `.log/README.md` says exactly this, rather than overselling it.

### 4.5 Two properties that hold by construction

- **One write path.** `log-append.py` (one session, straight to the log) and `log-land.py` (one
  package's staged events, after it integrates) both write through the same three functions of
  `eventlog.py`, so an event one refuses the other refuses too. The writer refuses to append onto a chain that does
  not verify, so a break is never buried under later records, and it refuses an event that the
  stream's projection could not fold. That second refusal matters because the log is append-only:
  an unprojectable event could never be taken back, and the projection would stay unbuildable.
- **The rendering is a pure function of the log.** No render-time timestamp, no unordered
  iteration, nothing derived from `seq`. It has to be, because `projection-fresh` compares the
  committed file to a fresh rebuild byte for byte and would otherwise cry wolf.

---

## 5. Layer three — enforcement

Two invariants of the pack are properties of a *change*, not of a snapshot, so `check-docs`
cannot see them: a locked file must not change at all, and an append-only file must never lose a
line. They are read from the diff instead.

### 5.1 The lock manifest

`.doc-locks`, one `tier: glob` per line, **last matching rule wins** — so promoting a file is a
line appended at the end, and the manifest is its own history of promotions. A path matching
nothing is `free`. Because a demotion would be an equally legal append, the guard compares the
manifest before and after every change that touches it and refuses any path whose tier would go
down, whichever glob does it (**demotion rule**); tiers only ever go up. The manifest, the guard,
the ceremony script and the hooks are hard-locked from the first commit, so a change to any of
them is a ceremony.

| Tier | Meaning | Held by, at Stage C |
| --- | --- | --- |
| `hard-locked` | may not change at all | `docs/inputs/**` — what the owner actually said |
| `append-only` | existing lines may never be removed or modified; additions allowed anywhere | `.log/events.jsonl`, `UNLOCKS.md` |
| `free` | mutable by design, listed explicitly so mutability reads as a decision | the living documents, the two projections, `specs/` until the freeze |
| `hard-locked` (the layer itself) | as above | `.doc-locks`, `scripts/lock-guard.py`, `scripts/unlock.sh`, `.githooks/**` |

`free` does not mean unguarded. `DECISIONS.md` and `QUESTIONS.md` are free because they are
generated and the rebuild has to be able to write them; `projection-fresh` is what stops a hand
edit from surviving. Tiers are promoted as the pack matures, never assumed: a file is locked when
the stage that legitimately writes it is over, which is why the freeze is what promotes `specs/`
to `hard-locked` — through `make unlock PATH=.doc-locks`, so the freeze itself is a recorded
ceremony.

### 5.2 The guard and the hooks

`scripts/lock-guard.py` is a pure function of (diff, manifest, token) → violations. One rule
catches both deletions and modifications in an append-only path: **any removed line**, since a
modified line appears as a removal plus an addition. Creating a path that did not exist is
allowed under a hard-locked glob — nothing is locked yet, and the file is immutable from that
commit onward.

The hooks are transport and contain no rules, so the local check and the server check cannot
drift apart:

| Hook | Runs | Purpose |
| --- | --- | --- |
| `pre-commit` | before a commit | the guard over the staged diff; blocks on any violation |
| `post-commit` | after a commit | consumes the single-use unlock token, re-locks the file |
| `pre-receive` | on the remote | the same guard over the pushed diff |

`git commit --no-verify` skips the local hook; nothing in a client-side hook can prevent that.
The local hook is fast feedback; **the pre-receive mirror on the remote is the enforcement** — it
runs where the committer's flags do not reach. Both read the manifest that judges a change from
*before* it (`HEAD`, or the revision being replaced), never from the change itself, and hand the
guard the manifest *after* it for the demotion rule — so a push cannot relax a lock and break it
in the same breath, nor relax it in one push and use the relaxation in the next. A repository
without such a remote has feedback and no enforcement, and should say so rather than assume the
locks hold.

**What the remote does and does not guarantee.** It guarantees that no hard-locked path changes
without a reason for that exact path travelling in the same change, that no append-only file
loses a line, and that no tier is ever lowered. It does **not** guarantee that the reason was
anyone's but the committer's: the record in `UNLOCKS.md` is a line of text, and whoever can push
can write it. The ceremony is therefore an audit trail — nothing changes silently, and every
change to a locked file names a who, a when and a why — not an approval gate. That matches the
threat model of the whole layer: an agent drifting, not a committer forging. Approval of a change
is what the owner reads in `UNLOCKS.md` and the `adr` events afterwards, and signing the records
would be a different mechanism. The demotion rule is the one absolute: no ceremony lowers a tier,
so a promotion made by mistake is undone only by an administrator of the remote, deliberately,
outside the tooling.

### 5.3 The unlock ceremony

Changing a hard-locked file is possible, deliberate and self-documenting:

```bash
make unlock PATH=docs/inputs/requirements.md REASON="the owner sent a corrected page"
```

It refuses any path the manifest does not call hard-locked, appends a record to `UNLOCKS.md` and
stages it so the change and its reason travel in one commit, makes the file writable, and writes
a single-use token the guard accepts for exactly that path. The next commit consumes it: the file
returns to `0444` and the token is deleted. One ceremony, one deliberate change.

Two evidence paths exist because the server never sees the token: the token satisfies the local
hook, and the `UNLOCKS.md` record added in the same diff satisfies the push (see the limits above:
it is evidence that a reason was recorded, not proof of who approved it). Stage C also sets the
hard-locked files read-only, so an accidental in-session overwrite fails at the filesystem before
it reaches a commit. Git records only the exec bit, so that mode is local to the clone and
`make install-hooks` runs once per clone; the hooks, not the mode bits, are the enforcement.

---

## 6. How it runs

There is no state file. The stage is derived from what exists in the target repository:

```bash
scripts/stage-detect.sh <target>
```

| Verdict | Meaning |
| --- | --- |
| `A-intake` | no `QUESTIONS.md`, no `docs/inputs/` |
| `A-extract` | inputs saved, `QUESTIONS.md` holds no card yet |
| `A-cards` | a card blocking the specification has no answer — in any stage: every card opens Blocking, and only the owner's deferral moves it to Open |
| `B-fileset` | no `specs/README.md` |
| `B-write` | files in the spec map are missing |
| `C` | specs complete, no `AGENTS.md` |
| `D` | `AGENTS.md` exists, baseline not stamped |
| `frozen` | baseline stamped; changes go through the amendment regime |

It reads the projections and the documents, never the log. What the machine decides the stage
from is what a person can open and read: an event that has not been rendered yet moves nothing.

| Stage | Rounds | Ends when |
| --- | --- | --- |
| **A — Elicit** | intake, extract, then one batch per surface | no card blocking the specification lacks an answer |
| **B — Specify** | file set, foundations, domain files (max four per round), register, plan and playbook | zero unratified statements remain |
| **C — Operationalize** | one round: verbatim assets, living documents, compile `AGENTS.md`, leakage check | `make check-docs` exits 0 |
| **D — Review** | hunter rounds, mechanical pass, owner read, freeze | the owner says freeze, explicitly |

Stage A and B stop for the owner. Stage C needs no owner input: everything in `AGENTS.md` is
compiled from the pack, and if compiling exposes a missing decision it becomes a card, never an
improvised sentence. An existing spec set the owner adopts as-is skips A and B and enters at C.

---

## 7. Standardized shapes

Every artifact has a fixed shape, because a line-oriented script has to verify it.

### The decision card, as the projection renders it

```markdown
### Q-004 — Records shared between the two shops
- Surface: data
- Source: "two car repair workshops in Attica (one in Peristeri, one in Glyfada)"
- Question: Are customers and vehicles one shared set of records, or does each shop keep its own?
- Options:
  - A) Everything shared, including jobs → effect on data: one history regardless of shop, and no
    notion of which shop a job belongs to, so the weekly figures have nothing to group by.
  - B) Each shop keeps its own → effect on data: the same car has two independent histories.
  - C) Customers and vehicles shared, jobs owned by the shop that did the work → effect on data:
    history follows the car, and every job carries the shop as part of its identity.
- Recommendation: C, because the two promises pull in opposite directions: the history follows
  the car, the weekly numbers follow the shop.
- Blocks: specification
- Answer: C (2026-09-04; recommendation accepted)
```

`Blocks:` is `specification` when a card opens, always; `log-append` refuses anything else. When the
owner defers a card, the `card-deferred` event sets `Blocks:` to the phase or work package the answer
changes. A deferred card carries no answer and is raised again before the
phase it blocks.

### The events behind that card

```json
{"seq":7,"ts":"2026-09-04T09:12:00Z","actor":"agent","stream":"questions","type":"card-opened","payload":{"id":"Q-004","title":"Records shared between the two shops","surface":"data","source":"...","question":"...","options":["A) ... → effect on data: ...","B) ..."],"recommendation":"C, because ...","blocks":"specification"},"prev":"9f2c...","hash":"41ab..."}
{"seq":8,"ts":"2026-09-04T09:40:00Z","actor":"owner","stream":"questions","type":"card-answered","payload":{"id":"Q-004","answer":"C","date":"2026-09-04","recommendation_accepted":true},"prev":"41ab...","hash":"7d03..."}
```

### Provenance tag

```markdown
- Every write MUST derive the shop context server-side, never from a client-supplied ID. [input]
- Guest credentials MUST be separate from staff session cookies. [Q-004]
- The API base path MUST be `/api/v1`. [D-006]
```

| Tag | Who decided |
| --- | --- |
| `[input]` | the owner, in the raw requirements |
| `[Q-NNN]` | the owner, by answering a card |
| `[Q-NNN, recommendation accepted]` | the owner, by accepting the proposal |
| `[D-NNN]` | the agent, touching no surface, alternatives recorded |
| `[inferred]` | nobody yet; zero of these remain at freeze |

### Decision entry, as the projection renders it

```markdown
## D-006 (2026-09-04) — API base path
Status: superseded by D-011
Type: implementation
Decision: …
Why: …
Alternatives: … (rejected: …)
Affected specs: …
```

Types are `implementation`, `spec-amendment` and `adr` (which carries
`Owner approval: pending | granted <date> | rejected`, changed by its own event). A superseded
record keeps its text and gains the status line; nothing is collapsed, nothing is deleted.

### Living documents, in their truthful-empty state

```markdown
# TRACEABILITY
| Package | Phase | Outcome | Key specs | Status | Evidence |
| FND-01  | 0     | …       | …         | not started | — |

# GAPS
| G-001 | Nothing exists beyond the documentation pack … | … | … | FND-01, then Phase 0 onward |

# PLAN
## Now
### FND-01 — Command contract and repository scaffold
- Acceptance (executable): `make verify` exits 0 from a fresh clone …
```

Nothing is `done` or `in progress` until a command ran and passed, and the skill runs no such
command. `PLAN.md` holds only `Now` and `Next`; git is the archive.

### Red line, in `AGENTS.md`

```markdown
- **Shop boundary is server-derived.** Every query filters by the shop of the authenticated
  session; a client-supplied shop ID is never trusted (`08` §2, `12` §4).
```

Eight to twelve of them, each a compression with citations. A red line that cites nothing means
the spec is missing the statement, which is a card or a recorded default, not a new sentence.

### Manifest line and unlock record

```
append-only: .log/events.jsonl
hard-locked: docs/inputs/**

- unlock 2026-09-04T11:20:07Z path="docs/inputs/requirements.md" by="owner" reason="corrected page"
```

---

## 8. The gates

`make check-docs` runs `scripts/check-docs.py`, copied verbatim into the target. Python 3
standard library, and it runs before any code exists.

| Rule | Asserts |
| --- | --- |
| `citations` | every `NN` §M and `README.md` §Name citation resolves to a real heading (a §Name is the longest heading the text starts with, so prose may follow); the body of a superseded decision is history and is not checked |
| `now-items` | no `Now` item is already `done`; every `Now` item has a traceability row |
| `plan-size` | `PLAN.md` stays under its line ceiling |
| `gaps` | every package or phase a gap cites exists; gap IDs unique and increasing |
| `packages` | every work package has exactly one traceability row, and no row lacks a package |
| `traceability` | status values are allowed, and `done` and `in progress` rows carry evidence |
| `decisions` | D-IDs monotonic and contiguous, required fields present, ADRs carry approval, index matches |
| `register` | the locked register carries only `[input]` or resolved `[Q-NNN]` |
| `provenance` | every tag resolves; every resolved card is cited, unless superseded, in which case its successor must exist |
| `normative-tagged` | every normative statement in `specs/`, the spec map included, ends with a provenance tag (adopted packs exempt by declaration) |
| `inferred-zero` | once the baseline is stamped, no `[inferred]` remains in `specs/`; before it, reported only |
| `cards` | every open card has all six fields and a valid surface |
| `chain-intact` | every hash recomputes, every `prev` links, `seq` is contiguous from 1 |
| `projection-fresh` | `DECISIONS.md` and `QUESTIONS.md` equal a fresh rebuild, byte for byte |
| `red-lines` | every red line cites at least one spec section |
| `commands` | every command listed in `AGENTS.md` is a real Makefile target |
| `agents-size` | `AGENTS.md` stays under 20 KB |
| `gaps-size` | no cell of a `GAPS.md` row exceeds 2000 characters: a row holds one gap, not the history of the packages that narrowed it |
| `evidence-size` | no Evidence cell of `TRACEABILITY.md` exceeds 1000 characters: it holds the run that proved the current status, and Git holds the earlier ones |
| `layer-notes` | every `done` package has `docs/layers/<PACKAGE>.md` with its three headings and a line in the `AGENTS.md` index; every note names a package the plan defines; no `AGENTS.md` heading names a work package |
| `markers` | no unrendered placeholder and no `TBD` survives |
| `task-policy` | every work package states `Surfaces`, `Touches red line`, `Contract change`, `File surface`, `Lane` and `Depends on`; the two derived ones equal what the pack derives from its own cards, register and red lines; the lane is one the plan lists; `Depends on` stays inside the phase, forms no cycle, and lists every `Contract change: yes` package of the phase whose section the package cites; the prompt-selection table in `AGENTS.md` names only the four real prompts and only characteristics the rule defines |

Targets that are real from the first commit: `check-docs`, `check-locks`, `verify-chain`,
`rebuild-decisions`, `rebuild-questions`, `install-hooks`, `unlock`. Every other target in the
contract fails with a message naming the work package that will deliver it, so a missing gate and
a passing gate never look alike.

`make check-docs` depends on `verify-chain`. It deliberately does **not** depend on the rebuild
targets: that would repair a drifted projection instead of failing on it. `check-docs.py --only
RULE,RULE` scopes a run to the rules that can hold before every document exists (the stages use it
before Stage C); its summary says how many failures of other rules it dropped, so a scoped run
never reads as a clean one.

`scripts/check-docs.py --task PACKAGE|all` is the same script read rather than run as a gate. It
prints, per work package, the two derived characteristics, the recorded `Contract change` and the
live `blocked-by`. Stage B and Stage C use it to write the stored fields; an implementation
orchestrator uses it to decide which session prompts a task needs, without a judgement pass of its
own.

`scripts/extract-normative.py` lists every normative statement with its file, section, line and
tag. It runs after every writing round and its output is the hunter's input.

The design rule behind all of it: **a rule that can be an assertion is one**, and is then deleted
from the prose. Extended once: **a lock that can be enforced is enforced.** `AGENTS.md` says only
what no script can check.

---

## 9. Invariants

- Rounds, never one shot. A stage that has not reached its stop does not skip ahead, even when
  asked to "just generate it".
- Never answer a surface question on the owner's behalf. Write the card, recommend, wait.
- Living documents start truthful-empty.
- Decisions and cards are recorded by appending an event and rebuilding, never by writing into
  the projection.
- Retire a record by superseding it. Never by deleting it, never by editing an answer.
- Every card opens Blocking; only the owner's word defers it. The skill never appends
  `card-deferred` on its own.
- One home per rule; the files point at each other and never repeat each other.
- Spec sections are never renumbered after the first owner review. Content appends.
- Never add scope. A missing requirement whose absence matters is a card.
- Never lock a file a later stage still legitimately writes; promote the tier instead.
- The generated repository never references the skill, its templates or its process.
- Copy mechanisms, not domain. The exemplar's tenancy model and screens never leak into another
  product's pack.

---

## 10. Layout of the skill

| Path | Role |
| --- | --- |
| `SKILL.md` | the operating prompt: start here, the mechanisms, the hard rules |
| `reference/surfaces.md`, `decision-card.md`, `provenance.md` | the core mechanisms, read every session |
| `reference/elicitation-checklist.md` | the sweep that keeps Stage A from under-asking |
| `stages/A-elicit.md` … `D-review.md` | the rounds of each stage and where each stops |
| `stages/hunter.md` | the two fresh-agent prompts |
| `templates/` | the rendered assets, each with its placeholder notes |
| `templates/scripts/eventlog.py` | chain primitives, event validation, both projections |
| `templates/scripts/log-append.py`, `log-land.py`, `verify-chain.py`, `rebuild-decisions.py`, `rebuild-questions.py` | the two writers over one write path (one session; one landed package), the chain check, the two rebuilds |
| `templates/scripts/check-docs.py`, `lock-guard.py`, `unlock.sh` | the gates and the ceremony, copied verbatim |
| `templates/githooks/`, `templates/.doc-locks`, `templates/UNLOCKS.md`, `templates/log-README.md` | the enforcement layer's assets |
| `templates/decisions-seed.json` | the five regime records a fresh log starts with |
| `scripts/extract-normative.py`, `scripts/stage-detect.sh` | the mechanical passes |
| `scripts/test-lock-guard.sh`, `test-decisions-log.sh`, `test-questions-log.sh`, `test-land.sh` | the acceptance suites |

---

## 11. The acceptance suites

Each runs in a throwaway repository and exits non-zero on any wrong behaviour.

| Suite | Cases | Covers |
| --- | --- | --- |
| `test-lock-guard.sh` | 26 | append-only removals, hard-locked changes, the ceremony end to end (including a commit that deletes the unlocked path), the `--no-verify` bypass and its server-side mirror, the demotion rule locally and over a demotion-only push, the guard's self-protection, a promotion with and without the ceremony, two ceremonies in one commit with both paths authorized and both re-locked, plus twenty-four policy unit cases over crafted diffs and manifests, among them a new binary file under a locked glob, and the two `docs/` tiers side by side (a layer note and the gotchas file free, the raw inputs refused, in one commit) |
| `test-decisions-log.sh` | 17 | append, rebuild, determinism, supersession, a tampered log line, a hand-edited projection, the refusal to append onto a broken chain, and the events no projection can fold (an ID that skips ahead, an approval aimed at a non-ADR) |
| `test-questions-log.sh` | 34 | cards opened, answered, deferred, reactivated, resolved and superseded; the provenance seam from both sides; interleaved streams rendering identically to separated ones; refused events including a card ID that skips ahead; and that `stage-detect` reads the projection rather than the log |
| `test-check-docs.sh` | 32 | the `check-docs` rules one at a time over minimal fixtures: `markers` over the root Makefile, `cards` contiguity, `normative-tagged` (code spans, fences, tables and lead-in inheritance; the adopted-pack exemption), `inferred-zero` before and after the baseline stamp, that `extract-normative` reads the same detector, `gaps-size` and `evidence-size` (a cell past each ceiling failing with its length, an ordinary row of each passing, and a gap row naming four packages reported without failing), a drift check between `reference/events-and-rules.md` and the two scripts it documents (every rule name in the checker, every event and every required decision field in the log tooling), and `layer-notes` in seven shapes (a `done` package without a note, a note missing a heading, a note absent from the index, the clean pair, the shipped README and `_`-prefixed files, a note naming no package, and a section per package in `AGENTS.md`) |
| `test-task-policy.sh` | 29 | the `task-policy` rule and the `--task` reader over a fixture pack: a package citing a security-surfaced section, one citing none, a hand-edited `Surfaces`, a red line moving onto a package that denies it, four ways the policy table can lie, the field shapes, a package written as a single line whose citations sit on that line, and `blocked-by` answering live while the plan file stays byte-identical; then `--brief` over the same fixture: every section once in the fixed order with its counts, the cited spec text and the dependency's layer note carried in full, only the rows naming the package, the byte-count footer, a plan byte-identical afterwards, an unknown package exiting non-zero, a blocking card carried with its options, and a retitled section still resolving; then the two scheduling fields: a package without a file surface, a lane the plan does not list, the five passing together, a judgement the rule refuses to second-guess, an overlap reported by both `--task all` and the gate without failing either, and both fields reaching the brief |
| `test-stage-detect.sh` | 11 | a target walked through every state — empty, inputs saved, cards Blocking, answered, deferred, spec map, files, `AGENTS.md`, baseline — with the verdict asserted at each, including a Blocking card raised during Stage B |
| `test-allowed-tools.sh` | 2 | every backticked shell command in `stages/*.md` and `SKILL.md`, split into subcommands the way Claude Code matches them, is pre-approved by an `allowed-tools` pattern |
| `test-render.sh` | 36 | every template rendered for a fixture product per Stage C1–C2, the log seeded with the regime records and two cards: `make check-docs`, `verify-chain`, both projections fresh and byte-stable, no placeholder or skill reference left, `stage-detect` walking C → D → frozen, the lock layer over the first commit, the freeze promotion as a ceremony and the guard's self-protection, one broken red line failing the gate, one hand-edited task characteristic failing it, the layer-note seam through the whole gate (a package reaching `done` without a note fails; the note plus its index line passes; a per-package section in `AGENTS.md` fails), and `make brief` on the rendered pack: it exits 0, resolves the cited spec text, is smaller than the documents it replaces, and prints a usage line without a `TASK`; and the prompts' own rules: prompt 1's second exit at the session budget, prompt 2 running where it did not write the code, the two registers declaring their own ceilings, and every package of the rendered plan carrying a file surface and a lane |

They are worth running against a mutation, not only against the current code: disabling the hash
comparison, dropping a stream filter, leaking `seq` into a rendering or removing the supersession
exemption each fail a specific, named case. The same holds for the templates: renaming the
`## Commands` heading in `templates/AGENTS.md` or dropping a target from `templates/Makefile`
fails `test-render.sh` with the `commands` rule named.

---

## 12. What it does not do

It writes no code, runs no build, and stamps no baseline on its own initiative. It does not decide
anything on a surface. After the freeze it is out of the loop: changes go through the amendment
regime in the generated `AGENTS.md`, which is now a `make unlock` plus a recorded event, not
another invocation of the skill.

One number tells whether it worked: **owner interventions per work package during
implementation**. If it rises, Stage A under-elicited a surface, and
`reference/elicitation-checklist.md` is the file that gets amended.

---

## 13. How to verify this pack

Five properties carry everything above. None of them is a claim to be taken on trust; each has a
command. The first three and the fifth run inside a generated pack; the numbered cases run from
the skill's own suites.

### P1 — Both projections are pure functions of the log

If a rendering is not byte-stable, `projection-fresh` fails on a clean repository and the whole
record layer becomes noise. The sharpest cheap probe is hash randomization: `PYTHONHASHSEED`
changes set iteration order between runs, so any unordered iteration that reached the output
shows up as a differing digest.

```bash
for r in decisions questions; do
  for seed in 0 1 2 3 4; do
    PYTHONHASHSEED=$seed python3 scripts/rebuild-$r.py --stdout | sha256sum | cut -d' ' -f1
  done | sort -u | sed "s/^/$r /"
done
```

**Pass: exactly one digest per renderer**, so two lines in total. Two lines for one renderer means
something unordered, or something about the moment of rendering, leaked into the file.

### P2 — The chain verifies and the projections match it

```bash
make verify-chain     # every hash recomputes, every prev links, seq contiguous from 1
make check-docs       # includes chain-intact and projection-fresh for both projections
```

**Pass: both exit 0.** `verify-chain` names the first broken link and stops there, because nothing
after a break is verifiable. `projection-fresh` rebuilds into a buffer and compares byte for byte,
so a hand edit to either projection fails the gate instead of becoming the record. `check-docs`
depends on `verify-chain` and deliberately does not depend on the rebuild targets: a gate that
repairs the drift it is meant to detect is not a gate.

### P3 — Neither stream can disturb the other

Both streams share one file and one sequence. A projection must depend only on its own records,
never on where they sit in that sequence.

```bash
~/.claude/skills/design-pack/scripts/test-questions-log.sh    # cases 9, 9b, 9c, 9d
```

Case 9 asserts the fixture really is interleaved (`dec, q, dec, q`, seq 1..4); 9b and 9c render
the woven log and a separated log of the same events and require the two `DECISIONS.md` and the
two `QUESTIONS.md` to be identical byte for byte; 9d confirms the woven chain verifies while the
two logs themselves differ, which is the point — the renderings match although the records do
not. The timestamp is pinned to one value across the fixtures, so interleaving is the only
variable.

### P4 — The machine reads what the human reads

`stage-detect` decides the stage from the projection, never from the log. Otherwise a record that
exists but has not been rendered would move the stage without appearing in the file a person
opens.

```bash
~/.claude/skills/design-pack/scripts/test-questions-log.sh    # cases 10, 10b, 10c
```

Case 10 appends a blocking card and does **not** rebuild: the verdict must not move. 10b rebuilds
and requires the same card to move it to `A-cards`. 10c greps `stage-detect.sh` for `.log` and
`events.jsonl` and fails if either ever appears, so wiring it to the log later breaks the suite
rather than the coupling.

### P5 — Nothing of the skill reached the pack

The generated repository must not reference the skill, its templates or its process, and no
placeholder may survive rendering.

```bash
grep -rn '{{' . --include='*.md' --include=Makefile
grep -rniE 'design-pack|template notes|CLAUDE_SKILL_DIR' . | grep -v '^\./docs/inputs/'
```

**Pass: both silent.** The first is limited to markdown and the `Makefile` because
`scripts/check-docs.py` documents `{{` in its own rule list. The second excludes `docs/inputs/`,
which holds the owner's raw material verbatim and is not the skill's to police.

### The whole layer at once

```bash
cd ~/.claude/skills/design-pack
sh scripts/test-lock-guard.sh        # 12 cases: locks, hooks, the ceremony
sh scripts/test-decisions-log.sh     # 11 cases: chain, projection, tamper, refusal
sh scripts/test-questions-log.sh     # 30 cases: cards, the seam, P3, P4
```

Run them against a mutation, not only against the current code. Disabling the hash comparison,
dropping a stream filter, leaking `seq` into a rendering, ignoring `card-deferred` in the fold, or
removing the supersession exemption each fail a specific named case; a suite that stays green
under those has proved nothing.
