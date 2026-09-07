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
a sentence above the table carries the requirement and its tag.

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

## At freeze

Zero `[inferred]` tags remain anywhere in `specs/`. Each one has become either a card
(surface touched) or a `[D-NNN]` (surface not touched). `check-docs` reports the
count per file; Stage D does not stamp the baseline while it is non-zero.

## Why the form is fixed

The method allows an inline comment, a trailing marker or a separate provenance table.
The generated pack uses the trailing marker everywhere because it is the only form a
line-oriented script can verify without parsing tables, and because a reader sees the
provenance at the point of reading rather than in another section.
