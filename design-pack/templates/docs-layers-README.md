<!-- TEMPLATE NOTES (delete this block when rendering)
Rendered into the target as `docs/layers/README.md` in Stage C, beside the (initially empty)
directory that will hold one note per work package. No placeholders.
The skill writes no note: nothing has been built when the pack is generated, and a note about
work that has not happened would be the same lie as a `done` row in TRACEABILITY.md.
-->
# Layer notes

One note per work package, `<PACKAGE>.md`, written by the session that delivers the package and
appended to by any later session that changes what the package established.

A note answers one question: **what does a later slice need to know about this layer in order
not to get it wrong?** It is written for the next agent, not for a reader of the history — the
names it will call, the rule it must not break, the reason a tempting alternative is already
refused. It is not a changelog, not a design essay and not a second copy of the specification:
the specification says what the product must do, and this says what the code now does about it.

`AGENTS.md` carries one index line per note and never the content. That is the whole point of
this directory: the entry point stays small enough to be read at the start of every session,
and a note is read only by the sessions whose package depends on it.

## Form

Three fixed headings, in this order. `make check-docs` (`layer-notes`) checks that a `done`
package has a note, that the note has these headings and that `AGENTS.md` indexes it.

```markdown
# <PACKAGE> — <the layer in four or five words>

## What this package established

The names a later slice calls and the shape it calls them in. Classes, endpoints, tables,
middleware, commands — with the one-sentence reason each exists where it does.

## What a later slice must not do

The alternatives this layer has already closed, and what breaks if one is reopened. This is
the half that saves a session: an agent that knows why the obvious second path is wrong does
not spend an hour building it.

## Handoff

Dated entries, newest last. One per session that touched the layer: behaviour changed,
commands run and their results, migration and rollback notes, follow-ups not implemented.
```

A package that established nothing a later slice can get wrong still has a note, and says so in
one line under the first heading. That is the same rule as a living document that reads
`not started`: an absence must mean one thing only, and an optional note would mean both
"nothing to say" and "no time to say it".

## Where each kind of knowledge goes

| Knowledge | Home |
| --- | --- |
| What the product must do | `specs/` — the contract, frozen |
| Why a judgement call went one way | `DECISIONS.md` — a `D-NNN`, through the log |
| What the code now does, for the next slice | here |
| What is deliberately missing | `GAPS.md` |
| What ran and passed | `TRACEABILITY.md` |
| What the tooling does that surprises an agent | `docs/gotchas.md` |
