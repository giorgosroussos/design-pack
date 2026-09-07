# Git hooks

Versioned here rather than in `.git/hooks/`, so they travel with the repository.
`make install-hooks` points git at this directory (`core.hooksPath`) and makes
the scripts executable. Run it once per clone.

| Hook | Runs | Purpose |
| --- | --- | --- |
| `pre-commit` | before a commit is created | `scripts/lock-guard.py --staged`; blocks the commit on any violation |
| `post-commit` | after a commit is created | consumes the single-use unlock token and re-locks the file |
| `pre-receive` | on the remote, before a push is accepted | the same guard over the pushed diff |

The hooks are transport. Every rule lives in `scripts/lock-guard.py`, so the
local check and the server check cannot drift apart.

## Why both

`git commit --no-verify` skips the local hook. That is by design in git and
nothing in a client-side hook can prevent it, so the local hook is fast feedback,
not a guarantee. The guarantee is `pre-receive` on the remote: it runs where the
committer's flags do not reach, over the same manifest and the same guard.

Install it by copying `pre-receive` into the remote repository's `hooks/`
directory and making it executable. A repository with no such remote has fast
feedback and no guarantee; say so rather than assuming the locks hold.
