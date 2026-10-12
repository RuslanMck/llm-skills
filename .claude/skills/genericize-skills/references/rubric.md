# The rubric — what "generic" means here

A generic skill works in a repo its author has never seen. It teaches principles, finds out how
the project is set up, and adapts. It never assumes a tool, folder, helper, vendor, or process
exists. Five principles, then the required shape.

## 1. Principles plus discovery, not placeholders

A placeholder like `<i18n-helper>` hides a name but keeps the assumption that the thing exists.
Replace it with:

- **The principle**: what good looks like and why.
- **A discovery step**: where the skill looks to find the project's version of it.

Where to discover things (use what applies):

| To learn | Look at |
|---|---|
| How tests run, projects, auth setup | `playwright.config.*`, `package.json` scripts, `Makefile` |
| How CI runs them | `.github/workflows/*`, `.gitlab-ci.yml`, other CI config |
| Folder layout, page objects, fixtures | the test folder tree, existing specs, imports |
| i18n | i18n libraries in `package.json`, locale files, `t(`/`useTranslation` calls |
| API contracts | schema libraries (zod, ajv, io-ts, OpenAPI), existing schema files |
| House rules | `CLAUDE.md`, `CONTRIBUTING.md`, READMEs in the test folders, lint config |

Before:
> Run `make <e2e-spec-target> SPEC=...` with the `<authenticated-project-name>` project.

After:
> Run the failing test the way CI runs it. Find the command in the CI workflow or the
> `package.json` scripts. If `playwright.config` gives a project `storageState`, every request
> context in that project inherits that login, so a "logged-out" probe may not be logged out.

## 2. Conditional rules, not assumed structure

When a rule depends on something only some projects have, write it as "If the project has X,
do A. If it does not, do B." Both branches must be useful. Never make a project without X look
wrong for lacking it.

Before:
> Take expected text from `<i18n-helper>(locale, key)`.

After:
> Don't hand-type user-facing text in assertions. Prefer semantic state (role, `aria-*`,
> `data-state`). If the project has i18n, take expected text from the translation source, keyed
> by the active locale. If it does not, keep expected copy in one test-data module rather than
> scattered across specs.

## 3. Project conventions win; project specifics stay out

- Every skill has a `## Before you start` section saying: read the project's own conventions
  (`CLAUDE.md`, contributing docs, test-folder READMEs, lint config); **where they conflict with
  this skill, the project wins.**
- Remove from the skill: product/company/vendor names used as the subject (not as an example),
  specific folder layouts presented as required, tag/ID schemes, custom helper names, custom
  guard scripts, ticket prefixes, environment names, branch names, issue trackers, CI hosts.
- A vendor or library may stay **as a labelled example** ("e.g. Zod", "e.g. a payment iframe
  such as Adyen") when the principle stands without it.
- Everything removed gets listed in the rewriter's output, so the user can move it into their
  project's own docs.

## 4. Short, opinionated, layered

- `SKILL.md` ≤ 250 lines. Longer detail goes to `references/<topic>.md`, linked from SKILL.md
  with one line saying when to read it.
- Don't teach what any Playwright/TypeScript user already knows (API basics, syntax). Keep the
  opinions, the checks, the traps and the reasons.
- Each rule: **rule → why → how to spot a violation → fix**. One to five lines each.
- Keep every rule from the source that is generic or can be made conditional. Shorter wording
  is fine; a lost rule is not.

## 5. Follow upstream best practice

When the source contradicts the tool's official guidance, follow the official guidance and note
the change in the rewriter's output. Known cases:

- **Locators**: Playwright recommends user-facing locators first: `getByRole`, `getByLabel`,
  `getByPlaceholder`, `getByText`, `getByAltText`, `getByTitle`; `getByTestId` when there is no
  stable user-facing handle; CSS/XPath last. Not "`data-testid` first, always".
- **Waiting**: web-first assertions and auto-waiting; no `waitForTimeout`, no
  `networkidle` as a readiness signal.
- **Isolation**: each test sets up its own state; no order dependence between tests.

## Required shape of a rewritten SKILL.md

```markdown
---
name: <kebab-case, matches the folder>
description: <what it does> Use when <concrete triggers: phrases, file types, situations>.
---

# <Title>

<2–4 lines: what this skill is for and what it is not for.>

## Before you start
<Read the project's conventions; they win on conflict. What to discover (from principle 1).>

## <Rule groups...>
<Each rule: rule → why → how to spot → fix. "If the project has X" branches where needed.>

## Checklist
<Short list a reviewer or author can run down.>
```

Review skills may add `## Report format` after the checklist. Keep the user's existing report
format when the source has one; it is already generic.

## Hard failures

- A `## Placeholders` section, or project placeholders in prose (`<e2e-dir>`, `<ticket-prefix>`).
  Angle brackets in a code example for an obvious example value are fine.
- A required project tool, script, helper, folder, or service with no "if the project has it"
  branch.
- Missing `## Before you start`, or it lacks the "project conventions win" rule.
- SKILL.md over 250 lines.
- A generic rule from the source missing from the rewrite.
- Raw control bytes (NUL, ESC) in any file.
