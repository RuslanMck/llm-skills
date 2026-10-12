---
name: commit-push
description: One-shot "Commit, push, open PR to <main-branch>. Skip gates and lefthook." Stage the changed paths explicitly, commit with LEFTHOOK=0, push the current feature branch, and open a PR into <main-branch> with the small-change gate-waiver note. Replaces typing that sentence by hand every time.
tags: [git, pr, commit, push, workflow, personal, gate-waiver, worktree]
trigger: When the user says "/commit-push", "commit push", "ship it", or any variant of "commit, push, open PR to <main-branch>, skip gates and lefthook". Do NOT invoke on a shared branch or for a change that touches schema/migrations, critical business logic, or auth/security code.
scope: USER-LEVEL — personal workflow. Lives in `~/.claude/skills/` only; do not copy it into a shared project repo.
---

# commit-push — commit, push, open PR to `<main-branch>` (gates + lefthook skipped)

The task this automates, verbatim: **"Commit, push, open PR to `<main-branch>`. Skip gates and lefthook."**

This is the project's sanctioned **small-change exception** (its `CLAUDE.md`, gates section): a
handful of files, no schema/migration, no auth/security surface, author confident
it can't break anything. CI is the verification gate. If the change is NOT that, stop and say so —
run `<gate-fast-command>` / `<gate-full-command>` instead of this skill.

## Placeholders

- `<company-name>` — the organisation or account that owns the repository.
- `<project-name>` — the repository name.
- `<main-branch>` — the repository's default/main branch name (e.g. `main` or `master`).
- `<ticket-prefix>` — the team key that starts ticket IDs in the tracker.
- `<review-state>` — the tracker state name that means "ready for review".
- `<gate-fast-command>` — the project's quick local gate command.
- `<gate-full-command>` — the project's full local gate command.

## Preconditions — check before doing anything

1. **On a feature branch, never `<main-branch>`.** `git branch --show-current`. If it prints `<main-branch>`,
   STOP — create a branch first, do not push to `<main-branch>` (project hard rule).
2. **Own feature branch, not shared.** `LEFTHOOK=0` and gate-waiving are only allowed on your own
   branch. If others are pushing to it, STOP.
3. **Change is genuinely small-and-safe.** Touches none of: `**/migrations/**`, schema, critical business logic,
   auth/session/security, `.github/**`, `docker/**`, `*.env*`. If it does, this
   skill does not apply — tell the user and run the real gate.
4. **A Linear ticket exists for the work** (project hard rule). If one is already tied
   (branch name, conversation, prior step), reuse it. If not and this is code-change work, ask
   before creating one — don't silently ship untracked work.

## Steps

1. **Stage explicit paths — NEVER `git add -A` / `-all`.** Multi-worktree rule (user `CLAUDE.md`).
   Stage exactly the files this change touched:
   ```bash
   git add <path> <path> ...
   git diff --cached --stat   # confirm ONLY the intended files are staged
   ```
   A multi-path `git add` aborts and stages nothing if one pathspec is bad — so verify the
   `--cached --stat` before committing.

2. **Commit with hooks skipped, message from a file** (avoids backtick/`$()`/`!` shell
   substitution in `-m`). Conventional style, scope, no AI co-author trailer:
   ```bash
   LEFTHOOK=0 git commit -F <scratchpad>/commitmsg.txt
   ```
   Message shape: `type(scope): summary` + a short body of what changed and why. End of body
   references the ticket (e.g. `<ticket-prefix>-1234`) but do NOT put a ticket ID in the *branch* name unless
   the branch actually fixes that ticket (Linear auto-closes on merge).

3. **Push the current feature branch** (upstream if new):
   ```bash
   LEFTHOOK=0 git push -u origin "$(git branch --show-current)"
   ```

4. **Open the PR into `<main-branch>`** with the waiver line in the body:
   ```bash
   gh pr create --repo <company-name>/<project-name> --base <main-branch> \
     --head "$(git branch --show-current)" \
     --title "<same as commit subject>" \
     --body-file <scratchpad>/prbody.md
   ```
   The PR body MUST include, verbatim:
   > local gates waived — small change; CI is the verification gate.
   and the ticket reference. If the project uses third-party tools of this kind, update this skill to handle them. If it does not, skip this instruction.

5. **Update the Linear ticket** (don't wait to be asked): attach the PR link and move state to
   `<review-state>`. Use the Linear MCP or the tracker's CLI.

6. **Report**: commit SHA, branch, PR URL, ticket state. Past tense, with the URL.

## Hard NOs

- Never `git push origin <main-branch>`, never merge the PR (a human developer merges — project rule).
- Never `git add -A`/`--all`/`../...` in the multi-worktree setup.
- Never mask a failing test or use the waiver to get a known-red change past CI.
- Never skip hooks on a shared branch.

## Related

- `~/.claude/CLAUDE.md` (worktree isolation, explicit staging) and the project's `CLAUDE.md`
  (small-change gate exception, automation rules, commit style).
- This skill is an explicit request for the agent to run commit, push and PR itself. That
  overrides the default of handing the push over to the user, for this invocation.
