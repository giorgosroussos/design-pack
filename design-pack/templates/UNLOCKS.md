<!-- TEMPLATE NOTES (delete this block when rendering)
Seeded empty in Stage C, alongside .doc-locks and scripts/lock-guard.py. Append-only
by manifest rule. Records are written by scripts/unlock.sh, never by hand; the guard
reads the added lines of this file to authorize a hard-locked change in a push it did
not witness locally, so the machine-readable form matters.
No placeholders.
-->
# UNLOCKS

One line per ceremonial unlock of a hard-locked path, appended by `make unlock`.

A hard-locked file cannot be changed by an ordinary commit. `make unlock PATH=<path> REASON="..."` records the intent here, makes the file writable and authorizes exactly that path for exactly one commit. The record and the change it permits travel in the same commit, which is what lets the remote verify a push it did not witness locally: the guard reads the lines added to this file.

Format, machine-read by `scripts/lock-guard.py`:

```
- unlock <ISO-8601 UTC> path="<path>" by="<name>" reason="<why>"
```

Never edit or remove a line here. The point of the file is that it cannot be tidied.

## Records
