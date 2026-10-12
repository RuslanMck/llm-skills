# Rewriter brief (template)

The orchestrator fills the `{{...}}` fields and sends everything below the line as the
subagent prompt.

---

You are rewriting a Claude skill so it works on any project, not only the one it was written
for. Work only inside `{{target_dir}}`. Do not touch any other path. Do not commit.

**Target:** `{{target}}`, disposition `{{disposition}}`
**Scope:** {{scope}}
**Sources (read every one in full, including their `references/`):**
{{sources}}

**What sibling skills cover (do not duplicate them; link by name instead):**
{{plan_table}}

## Do this in order

1. Read `.claude/skills/genericize-skills/references/rubric.md`. It is the standard you are
   held to. Read it fully before anything else.
2. Read every source file in full.
3. **Build the rule inventory before writing anything.** List every rule, check, trap, or
   instruction in the sources, one per line, numbered:
   `R<n> | <source file>:<line> | <the rule in ≤15 words> | <fate>`
   where fate is one of:
   - `keep` — already generic
   - `generalize` — becomes a principle + discovery step (rubric 1)
   - `conditional` — becomes "if the project has X…" (rubric 2)
   - `example` — kept only as a labelled example (rubric 3)
   - `project-only` — removed; goes on the removed list
   - `upstream-fix` — changed to follow official guidance (rubric 5); say what changed
   - `sibling:<name>` — belongs to another target in the plan
   Every rule must get a fate. When unsure between `project-only` and `conditional`, pick
   `conditional`: losing a good rule is worse than an extra branch.
4. Write `{{target_dir}}/SKILL.md` in the rubric's required shape. Every `keep`,
   `generalize`, `conditional`, `example` and `upstream-fix` rule must appear in SKILL.md or a
   `references/*.md` file linked from it. SKILL.md ≤ 250 lines.
5. Run `bash .claude/skills/genericize-skills/scripts/check.sh {{target_dir}}` and fix every
   `FAIL`. For each `REVIEW` line, either fix it or be ready to justify it.
6. If you are fixing a checker's findings (below), fix each one and say how.

{{checker_findings}}

## Return exactly this

```
FILES
<each file you wrote>

RULE INVENTORY
<the full numbered list from step 3, with fates; for kept rules add "→ <file>#<heading>">

REMOVED PROJECT-SPECIFIC MATERIAL
<bullets: what was removed and the source line, so the user can move it to their project docs>

UPSTREAM CHANGES
<bullets, or "none">

CHECK.SH
<the final output of check.sh>

OPEN QUESTIONS
<anything you could not decide, or "none">
```
