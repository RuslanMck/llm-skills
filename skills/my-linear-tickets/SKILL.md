---
name: my-linear-tickets
description: Pull the Linear tickets the user needs to be aware of — the union of created-by-me, labelled with a configured label, and assigned-to-me — as one sorted table with Creator and Assignee, excluding closed/merged noise. Use when asked "my tickets", "ticket statuses", "what do I need to be aware of", "my Linear list", or any recurring my-open-tickets check. Personal workflow skill, not a team standard.
---

# my-linear-tickets

Recurring status check: the tickets the user should be aware of, in one table.

## Placeholders

- `<company-name>` — the Linear workspace (organization) name.
- `<team-name>` — the Linear team whose issues are scanned.
- `<company-domain>` — the email domain shared by workspace accounts.
- `<project-name>` — the repo that ships the optional `<linear-cli>`.
- `<linear-cli>` — the name of the project's Linear CLI tool.
- `<qa-label>` — the Linear label name used to flag tickets for QA attention (e.g. `QA`).
- `<env-file>` — the env file that holds `LINEAR_API_KEY` for the CLI (e.g. `.env.local`).

## Inclusion — union of three (a ticket qualifies if it meets ANY)

1. `createdById` == me
2. `labels` includes `<qa-label>`
3. `assigneeId` == me

Resolve "me" via `mcp__claude_ai_Linear__get_user` with `me` (the user's id, workspace `<company-name>`, team `<team-name>`).

## Exclusions

- **Status:** drop `Ready to merge`, `Canceled`/`Cancelled`, `Duplicate` (match case-insensitively; both Cancel spellings).
- **Merged / Done by default:** these match the criteria but are completed noise (usually 250+ of them). Show only the OPEN set (not Merged/Done) unless the user explicitly asks for merged/completed too. Say once that N merged were set aside.

## Tooling

- The `<linear-cli>` from `<project-name>` is the documented path BUT needs `LINEAR_API_KEY` in `<env-file>`, which is usually absent in the worktrees — check, and if missing fall back to **Linear MCP** (`list_issues` / `get_issue` / `get_user`).
- `list_issues` has **no creator filter**. Cover created-by-me by listing team `<team-name>`, `orderBy updatedAt`, `limit 250`, then filtering `createdById` client-side. Assigned-to-me and the configured label each have a direct filter (`assignee: "me"`, `label: "<qa-label>"`).

## Handling the volume (important)

`list_issues` results are large (100k+ chars) and get saved to a file. **Do this inside a subagent** so the bulk stays out of the main context. Instruct the subagent to:

1. Run three `list_issues` calls (assignee me · label `<qa-label>` · team `<team-name>` by updatedAt), each `limit 250`, `fields ["id","title","status","createdBy","assignee","labels","createdById","assigneeId","url"]`. Parse the saved files via python `json.load` / `read()[A:B]` slicing.
2. Union by `id`; apply the status exclusions; split Merged/Done from open.
3. For Creator/Assignee show display names; `—` for unassigned; shorten `*@<company-domain>` to the local part.
4. Fill any still-missing target via `get_issue`.
5. Return ONLY the final markdown table + total + the cap caveat. Nothing else.

## Output

One table, columns: `ID | Title | Status | Creator | Assignee`.
Sort by status in this order — **In Progress, ⏳To Review, Blocked, Todo, Triage, Backlog** — then numeric ID ascending within each status. Quote IDs and titles verbatim.

## Caveat to always state

The created-by-me fetch is capped at 250 rows (no server-side creator filter), so a ticket the user created that is older than the 250 most-recently-updated AND not matching the configured label AND not assigned to the user can be missed. Offer a complete paged sweep (page past the cap via `cursor`) if the user wants guaranteed completeness.

Read-only. Never mutate a ticket from this skill.
