# Provenance on every normative statement

Every `MUST`, `MUST NOT`, `SHALL`, `SHOULD`, `SHOULD NOT` and `MAY` in the generated
specs carries a trailing provenance tag. The form is fixed here so `check-docs`
and `extract-normative` can read it.

| Tag | Meaning | Who decided |
| --- | --- | --- |
| `[input]` | stated by the owner in the raw requirements (`docs/inputs/`) | owner, before the skill ran |
| `[Q-NNN]` | decided by the owner by answering card Q-NNN | owner, through a card |
| `[Q-NNN, recommendation accepted]` | same, the owner accepted the skill's recommendation | owner |
| `[D-NNN]` | agent default that touches none of the five surfaces, recorded with alternatives | the skill |
| `[inferred]` | agent inference not yet ratified | nobody yet |

## Form

The tag is the last thing on the statement's line:

```
- Every write MUST derive tenant context server-side, never from a client-supplied ID. [input]
- Guest credentials MUST be separate from staff session cookies. [Q-004]
- The API base path MUST be `/api/v1`. [D-006]
```

For a lead-in followed by a list, the tag on the lead-in line covers every item that
carries no tag of its own:

```
The MVP MUST: [input]

- provide a white-label public portal;
- enforce tenant and property boundaries; [Q-002]
```

A statement may carry several tags when it merges sources: `[input, Q-003]`. The
first tag is the primary one.

Tables in specs are not normative statements. If a table row must be normative,
a sentence above the table carries the requirement and its tag. A keyword inside a
code span (`` `MUST` ``) is a mention, not a statement; write it that way when prose
talks *about* the requirement language, as `specs/README.md` does.

The tag is the last thing on the line, always: `… Out of Scope. [input] A code change …`
leaves the statement untagged as far as any tool can tell.

## Where each tag may appear

| Location | Allowed |
| --- | --- |
| Locked decision register | `[input]`, `[Q-NNN]` only. Cited card must be Resolved. Enforced by `check-docs`. |
| Domain spec files | any tag. `[Q-NNN]` may cite an Open card (provisional, visible). |
| Spec map, plan, playbook, product traceability | `[input]`, `[Q-NNN]`, `[D-NNN]`. |
| Root living documents, AGENTS.md | no tags; they cite spec sections instead. |

## The two mechanical rules

1. **Register purity.** A statement in the locked register with any provenance other
   than `[input]` or a Resolved `[Q-NNN]` is a validation failure. The only way to keep
   such a statement is to turn it into a card and get an answer.
2. **Surface statements are ratified or carded.** A statement that touches data,
   security, scope, external commitments or UX and carries `[D-NNN]` or `[inferred]`
   is a finding for the assumption hunter, which writes it as a card. The hunter does
   not judge merit; the owner does.

## The two mechanical rules that hold everywhere

`check-docs` enforces the form in every generated pack, not only while the skill runs:

- **`normative-tagged`.** Every normative statement in `specs/` ends with a tag. An untagged
  `MUST` fails the gate, in a draft as much as in a frozen pack. (An adopted pack, one whose
  `docs/inputs/README.md` lists `specs/` itself as an authoritative input, is exempt: its
  statements are `[input]` by declaration.)
- **`inferred-zero`.** Once `specs/README.md` is stamped `Status: Implementation baseline`,
  no `[inferred]` remains anywhere in `specs/`. Before the stamp the count is reported and
  not enforced, because Stages B–D legitimately carry them.

## At freeze

Zero `[inferred]` tags remain anywhere in `specs/`. Each one has become either a card
(surface touched) or a `[D-NNN]` (surface not touched). `inferred-zero` fails the gate
otherwise, so Stage D cannot stamp a baseline over one.

A frozen pack **may** still cite an Open card. That is a deferral the owner chose, with its
`Blocks:` naming the phase or package before which it is answered, and the statement that
cites it reads as the recommendation until then. `check-docs` names every such statement in
its summary ("provisional statements … in a FROZEN pack") and does not fail on it; the owner
decided that freedom is worth more than the assertion. Session prompt 3 and the `Blocks:`
field are the net.

## Why the form is fixed

The method allows an inline comment, a trailing marker or a separate provenance table.
The generated pack uses the trailing marker everywhere because it is the only form a
line-oriented script can verify without parsing tables, and because a reader sees the
provenance at the point of reading rather than in another section.
