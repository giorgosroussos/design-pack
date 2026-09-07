# design-pack — overview and evaluation guide

## What it is

`design-pack` is a Claude Code skill. It takes raw product requirements and, through a
structured conversation with the person who owns the product, turns them into a
repository-ready documentation pack that a *separate* implementation agent can build from —
without ever going back to the person who wrote the requirements. It runs entirely inside
Claude Code, converses in the owner's language, and writes the pack itself in English. The
generated repository never references the skill or its process; it stands on its own.

## The problem it addresses

In agent-driven development, output quality is largely decided *before any code is written* —
by which decisions the owner made and which the agent made on its own. An agent that quietly
fills a gap ("assume email-and-password auth", "assume the weekly schedule is a fixed
template") produces a reasonable-looking specification whose assumptions nobody ever revisits.
That silent decision becomes a locked constraint downstream, and the cost of it surfaces weeks
later, in implementation.

`design-pack` exists to make the line between *owner decisions* and *agent decisions* explicit,
and to keep it that way. The owner decides only what the owner can meaningfully decide; every
other choice the agent makes is recorded together with the alternatives it rejected, so nothing
is both consequential and invisible.

## How it works

The skill runs in four stages. Stages A and B stop and wait for the owner; C and D mostly run
themselves.

**A — Elicit.** It reads the raw brief and, for every point where the inputs are silent on
something that moves one of five *surfaces* — data, security, scope, external commitments, or
UX — it raises a *decision card*: a single question, concrete options, the consequence of each
option on the relevant surface, and a recommendation. The owner answers per card, or accepts a
whole batch in one reply. Crucially, only those five surfaces generate questions for the owner;
anything that doesn't touch them (choice of framework, ID scheme, time-zone handling) the agent
decides itself and records — so the owner is not asked about things that aren't theirs to
decide, and is never *not* asked about things that are.

**B — Specify.** It writes the specification: numbered domain files, a locked decision
register, an implementation plan with work packages, and a playbook for the implementation
agent. Every normative statement (MUST / SHOULD / MAY) carries a tag identifying who decided
it — `[input]` (stated in the brief), `[Q-NNN]` (an answered card), or `[D-NNN]` (an agent
default, with its alternatives recorded). Nothing is left unattributed.

**C — Operationalize.** It compiles the operating layer: an `AGENTS.md` the implementation
agent reads first, the living tracking documents in an empty-but-truthful state, the command
contract, and the integrity machinery described below. This stage needs no owner input; if
compiling it exposes a missing decision, that becomes a card rather than an improvised sentence.

**D — Review.** Two fresh agents with no memory of the elicitation read the whole pack. One
rewrites, as a card, every surface-touching statement that isn't genuinely the owner's; the
other checks every `[input]` tag against the raw brief to catch anything the skill quietly
attributed to the owner that the owner never said. They run repeatedly until both return zero
findings. Then the owner reads the pack, names the product, and freezes it. After the freeze
the skill is out of the loop entirely — later changes go through an amendment regime defined in
the generated `AGENTS.md`, not through the skill again.

## Why "locked" is a guarantee, not a note

This is the part that separates it from a well-written prompt, and the part most worth a
critical eye.

The source of truth for decisions is an append-only, hash-chained event log. The human-readable
registers are *deterministic projections* of that log, rebuilt and compared byte-for-byte on
every check — so no hand-edit to a register can survive, and any tampering with recorded
history breaks the chain and is detected. Certain files are *hard-locked*; they can only change
through a ceremonial unlock that records who, when, and why in an append-only ledger, authorises
exactly one commit, and re-locks automatically afterward. Enforcement lives in git hooks and
filesystem permissions — the skill defines the contract, the environment enforces it, and the
implementation agent cannot quietly break an append-only or locked file even if instructed to.
A mechanical checker (`make check-docs`) verifies internal consistency on every run: every
cross-reference resolves, the locked register contains only owner decisions, no statement is
left untagged.

**Honest limits, stated up front.** The hash chain detects any edit to history but does not
authenticate authorship — it defends against accidental rewrites and silent drift, not a
determined adversary. Local git hooks can be bypassed with `--no-verify`; the server-side
mirror on the remote is the half that cannot. And the enforcement only becomes active once the
target directory is a git repository — before that, the policy is described correctly but
nothing enforces it.

## What it produces

A single repository containing: the numbered `specs/` (domain files, decision register,
implementation plan, agent playbook); an `AGENTS.md` entry point and its thin pointers; the
living state documents (`PLAN.md`, `TRACEABILITY.md`, `GAPS.md`, `QUESTIONS.md`, `DECISIONS.md`);
the raw inputs kept verbatim; the command contract (`Makefile`); and the integrity tooling
(the event log, the lock manifest, the git hooks, the check scripts).

## Its purpose, in one number

The measure of whether a pack was good is **owner interventions per work package during
implementation**. If the pack captured the right decisions, the implementation agent builds each
work package without going back to the owner. If that number rises, some surface was
under-elicited — and the thing that gets corrected is the skill's own elicitation checklist, so
the next pack asks where this one didn't.

---

## Installing and trying it (about 20 minutes)

You'll receive the skill as a folder named `design-pack`. You need Claude Code installed.

1. **Place the skill.** Unpack it so you have `~/.claude/skills/design-pack/SKILL.md` (and the
   `stages/`, `reference/`, `templates/`, `scripts/` subfolders beside it).

2. **Make a working directory and initialise git in it.** The integrity layer only enforces
   anything inside a git repository, so this step matters:
   ```
   mkdir -p ~/tmp/trial && cd ~/tmp/trial && git init
   ```

3. **Start Claude Code in that directory and invoke the skill:**
   ```
   /design-pack .
   ```

4. **Give it the requirements — either path works.** The skill asks for inputs at the start.
   There are two ways to try it, and they exercise different sides of it.

   *Quick path — paste a short brief.* Rough is fine; the elicitation is what turns its silences
   into questions. A small brief that touches all five surfaces works best. For example:

   > I run a small pottery studio. I want a web tool where members see the weekly class
   > schedule and book a spot; each class has a limited number of wheels. If a class is full,
   > members join a waitlist and get the spot if someone cancels. Members pay a monthly
   > membership — I track that in a spreadsheet now, but I'd like the tool to know who's active
   > so only they can book. Instructors need to see who's booked into their classes. I don't
   > want payments in the tool. I might open a second location one day, but not now.

   *Documented path — give it a real requirements file.* Instead of pasting a brief, you can put
   your actual requirements in a document — a PRD, a spec, or notes in a `.md` (or `.txt`) file —
   drop it in the working directory, and give the skill its path when it asks for inputs. This is
   closer to how the skill is meant to be used. It copies the file in verbatim and then elicits
   *only where the document is silent* — so where the requirements already settle something, it
   produces a tagged statement rather than a question, and it raises cards only for the genuine
   gaps. A well-documented input also gives the review stage (D) more to do, because one of the
   two review agents checks every requirement attributed to you against the source text, and the
   other flags anything the document quietly contradicts or assumes. This is the mode worth
   trying if you want to judge how it behaves on production-grade requirements rather than a
   conversational brief.

5. **Answer the decision cards.** Reply per card (e.g. `Q-003 B`), or say *"accept the
   recommendations"* to take a whole batch and move quickly. Try deliberately choosing *against*
   one recommendation — it's the clearest way to see the consequence propagate through the later
   specs.

6. **Let C and D run, then freeze.** When it asks, give the product a name and reply *"freeze"*.
   The skill will not freeze on its own.

7. **(Optional) See the enforcement bite.** After the freeze, try to hand-edit a line in a
   locked `specs/` file and commit it — the git hook rejects the commit. Changing it the
   sanctioned way requires `make unlock`, which records the reason and re-locks afterward.

## What to look for when evaluating

- Does it ask you *only* about things that genuinely change data, security, scope, external
  commitments or UX — and decide the rest itself, with alternatives recorded?
- When you deviate from a recommendation, does the consequence show up correctly in the later
  specs, tagged as your decision rather than the skill's?
- Does the review stage (D) catch anything the skill itself had quietly assumed and attributed
  to you?
- In the frozen pack, is *every* statement traceable — to your brief, to a card you answered, or
  to a recorded agent decision with its alternatives?
- Does "locked" actually hold — can a frozen spec be changed without the ceremony, or does the
  environment stop it?

