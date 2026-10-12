# Checker brief (template)

The orchestrator fills the `{{...}}` fields and sends everything below the line as the
subagent prompt.

---

You are checking a rewritten Claude skill against a written standard. **Do not edit any file.**
Report only.

**Target:** `{{target_dir}}`
**Sources it was built from:** {{sources}}
**The rewriter's rule inventory:**
{{rule_inventory}}

## Do this in order

1. Read `.claude/skills/genericize-skills/references/rubric.md` in full.
2. Run `bash .claude/skills/genericize-skills/scripts/check.sh {{target_dir}}`. Every `FAIL`
   line is a finding. For each `REVIEW` line, open the spot and decide: a project-specific
   leftover (finding) or a legitimate example (not a finding).
3. Read every file in `{{target_dir}}` in full.
4. **Rule coverage.** For each inventory rule whose fate is not `project-only` or `sibling:*`,
   find it in the new files. Missing or weakened beyond recognition → finding.
5. **Fate audit.** Pick the 5 `project-only` rules most likely to be wrongly removed and check
   them against the sources. A rule that holds for most projects, or that could be made
   conditional, was removed wrongly → finding.
6. **Shape.** Check each item in the rubric's "Required shape" and "Hard failures".
7. **Portability test.** Imagine three projects: (a) a small app with no i18n, no page
   objects, tests run with `npx playwright test`; (b) a large monorepo with i18n, custom
   fixtures and a strict CI; (c) an API-only service with no browser tests. For each, would any
   instruction in the skill be impossible to follow or make the project look wrong? Each such
   instruction → finding (unless the skill's scope already excludes that project).
8. **Upstream.** Any instruction that contradicts Playwright's official guidance (locator
   priority, web-first assertions, test isolation) → finding.

## Return exactly this

```
VERDICT: PASS | FAIL

FINDINGS
1. <file>:<line> — <what is wrong> — <rubric rule it breaks> — <the fix, as an instruction>
...
(or "none")

CHECK.SH
<its output>
```

`FAIL` if there is any finding from steps 2, 4, 6, 7 or 8, or a confirmed wrong removal from
step 5. Otherwise `PASS`. Be specific: a finding without a file and line is not a finding.
