<!-- TEMPLATE NOTES (delete this block when rendering)
Rendered into the target as `docs/gotchas.md` in Stage C, empty of content: no gate has been run
when the pack is generated, so every entry below would be invented. The implementation sessions
fill it. No placeholders.
-->
# Gotchas

What the tooling in this repository does that an agent cannot predict from reading it. Each entry
costs a session to learn, once; this file is where that session's cost stops being paid again.

Nothing here is a rule about the product — that is `specs/` — and nothing here excuses a failure.
A gate that fails for an environmental reason is **recorded here and named in the handoff**, never
retried until it passes: a red run is evidence, and a green one obtained by repetition is not.

## Gates that are known to be unreliable

One entry per gate, with the measurement behind it: how often it fails, under what conditions it
passes, and what a session should do instead of retrying. A gate with no measurement is not
unreliable, it is unexamined — say that rather than guessing.

*None recorded yet.*

## Tool output an agent cannot read

Runners that compact, suppress or reformat their output when they detect a non-interactive
caller, and the flag or environment variable that restores it. A tool that prints nothing and
exits non-zero belongs here the first time it costs anyone ten minutes.

*None recorded yet.*

## Environment traps

Ports, paths, locales, clock and container behaviour that differ between a developer's machine,
a session and CI, and what the difference does to a gate.

*None recorded yet.*
