---
name: genericize-skills
description: Rewrite project-bound skills in this repo's skills/ folder into generic, project-agnostic QA / Playwright / test-quality skills, fanning the per-skill rewrites and checks out to fast subagents. Use when asked to "genericize", "make generic", "de-project", or "rewrite the skills so they work on any project", for one skill or the whole library.
disable-model-invocation: true
---

# Genericize skills

Turns skills that were written for one project into skills that work on any project. You, the
session running this skill, are the **orchestrator**: you plan, dispatch, and do the final review.
Fast subagents do the per-skill rewriting and checking.

Read `references/rubric.md` before anything else. It is the definition of "generic" that every
step here, and every subagent, is held to.

Arguments: skill names or paths to rewrite (default: every skill under `skills/`), plus
optional `--model <haiku|sonnet|opus>` for the subagents (default `haiku`) and `--yes` to skip
the plan approval stop.

## Roles

| Who | Does | Why |
|---|---|---|
| Orchestrator (this session) | Inventory, target plan, merges/drops, final review, README | Judgment calls: what merges, what is project-only, whether a rule was lost |
| Rewriter subagent, one per target skill | Rule inventory, then the new SKILL.md (+ references) | Bounded, rubric-driven, parallel |
| Checker subagent, one per target skill | Runs `scripts/check.sh`, compares against the rule inventory | Fresh eyes; mechanical checks |

Spawn subagents with the Agent tool: `subagent_type: "general-purpose"`, `model: <--model>`,
run in the background, all rewriters for a phase in **one message** so they run in parallel.
Never let two subagents write to the same directory.

## Step 1 — Inventory (orchestrator)

1. List the target skills and their line counts: `wc -l skills/*/SKILL.md skills/*/references/*.md`.
2. Run `bash .claude/skills/genericize-skills/scripts/check.sh skills/<name>` on each one to see
   how project-bound it is today (placeholders, project terms, length).
3. Read each target's frontmatter and headings. Read in full any skill you are about to merge
   or drop. You decide merges; a subagent never does.

## Step 2 — Plan (orchestrator)

Start from `references/target-map.md` (the default proposal) and adjust it to what Step 1
found. For each **target** skill, write down:

- `target` — new skill name (kebab-case) and directory `skills/<target>/`
- `sources` — the old skill paths it is built from (one or several)
- `disposition` — `rewrite`, `merge`, `light-pass`, `move` (out of the QA library), or `drop`
- `scope` — one sentence: what it covers and what it does NOT (to stop overlap between targets)

Show the plan as a table and **stop for the user's approval** unless `--yes` was passed.
Merges, moves and drops are the user's call.

`move` and `drop` need no subagent. `move` = `git mv skills/<name> personal/<name>`;
`drop` = delete only after the user confirmed it in the plan.

## Step 3 — Rewrite (parallel subagents)

For each `rewrite` / `merge` / `light-pass` target, spawn one rewriter with the prompt in
`references/rewriter-brief.md`, filling in its `{{...}}` fields from the plan. Include the full
plan table in every brief so each rewriter knows what its siblings cover.

A rewriter writes only inside `skills/<target>/` and returns:
- the rule inventory (every rule from the sources, with its fate),
- the list of project-specific material it removed (the user may want it in their project's
  CLAUDE.md),
- the files it wrote.

A merge target whose sources are new and old at once (e.g. target name equals a source name)
writes into the same directory; it reads the sources first, then overwrites.

## Step 4 — Check (parallel subagents)

When a rewriter finishes, spawn a checker for that target with `references/checker-brief.md`,
passing the rewriter's rule inventory. The checker edits nothing; it returns `PASS` or `FAIL`
with numbered findings.

On `FAIL`, send the findings back to a rewriter (a fresh one with the brief + findings, or the
same one via SendMessage) and re-check. **At most 2 fix rounds per target.** Still failing →
the orchestrator fixes it or reports it to the user; do not loop.

## Step 5 — Final review and wiring (orchestrator)

1. Read every new SKILL.md yourself. Look for what the checker cannot judge: a rule that was
   generalised into something vague, two targets that now overlap or contradict, a description
   that would not trigger.
2. Delete the old source directories of merged targets (never before their target passed).
3. Update the root `README.md` with the skill index: name, one line, when to use.
4. Run `scripts/check.sh` on every target one last time.
5. Stage explicit paths only (never `git add -A`). Commit and push only if the user asked.

## Report to the user

One table: target · disposition · sources · lines before → after · check result · fix rounds.
Then the collected "removed project-specific material" lists, grouped by target, so the user
can move what they still need into their project. Then anything you could not resolve.
