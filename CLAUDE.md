# User-level instructions

## Multi-agent worktree isolation

A PreToolUse hook lives at `~/.claude/hooks/worktree-guard.sh`. It blocks
Edit/Write/NotebookEdit outside the current worktree root, blocks Read outside
the root unless the target is under `$HOME/.claude`, `/tmp`, `/var/folders`,
or `/etc/hosts`, and blocks obvious cross-worktree Bash patterns (`git add -A`,
`git add --all`, `git add ../...`, `git add /<path-outside-root>`,
`rm -rf /<path-outside-root>`, `cd ../..` chains). Pattern matching on Bash
is advisory only — `eval`, base64, heredocs, and `$VAR` expansion can bypass
it; the path checks on Edit/Write/Read are the real enforcement.

Kill switch: export `WORKTREE_GUARD=off` in the environment of the Claude
Code session to bypass the hook entirely (e.g. for legitimate cross-worktree
comparison work).

Never `git add -A` in this multi-worktree setup. Stage explicit paths.

Only one Docker stack should be running across all <project-name> worktrees
unless a second stack has been explicitly set up on isolated ports (see
`~/.claude/templates/<project-name>-docker-second-stack.env.example`).

Playwright runs serialize via a flock at `/tmp/<project-name>-e2e.lock`. If you
see a lock error, another agent is running specs against the shared stack —
wait or coordinate. The shared Playwright auth state under `tests/e2e/.auth/`
is what the lock protects.

## Source hygiene — no raw control bytes

Never embed raw control bytes (NUL `0x00`, ESC `0x1B`) in source files or
commit messages — use escapes (`\\u0000`, `\\x1b`) instead. A single raw NUL
makes Git classify the whole file as binary, so `git diff` prints "Binary
files differ" with no line-level diff (PR unreviewable), and `git commit`
rejects the message ("must be a string without null bytes"). The bytes are
invisible in the Read tool and most editors, so they spread by copy/paste.

To check, pipe directly (a shell truncates at the first NUL inside `$(...)`,
so command substitution under-reports): `cat file | tr -dc '\\000\\033' | wc -c`,
`od -c file`, `git diff --numstat` (`-  -  file` = binary), or `file <path>`.
Fix at the byte level (rewrite the file), not by retyping the invisible line.
