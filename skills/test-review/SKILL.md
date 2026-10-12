---
name: test-review
description: "Review test code (Playwright/TypeScript and other frameworks) for naming, single responsibility, DRY, assertion quality and oracles, locator and wait reliability, skip and fixme reasons, failure-message quality, and scope (app code off-limits). Use when asked to review, audit, or check test files, a spec, page object, fixture, support helper, or test PR — e.g. \"review this spec\", \"/test-review tests/checkout/cart.spec.ts\", \"review my changes\", \"audit the test helpers\"."
---

# Test Review

Reviews existing or changed test code and reports findings. It does not edit. It checks naming,
structure, assertion quality, reliability, skip reasons, failure messages and scope.

Not for writing tests from scratch, which is `playwright-test-design` (if installed). Locator
choice belongs to `playwright-locators`, waits to `playwright-waiting`, reproducing a failing test to
`test-failure-investigation`, schema strictness to `api-contract-testing`, and locale-agnostic
assertions to `multi-locale-testing`. Those skills, if installed, own the authoring rules. This one
checks compliance and cites them.

## Before you start

**The project's conventions win.** Where `CLAUDE.md`, `CONTRIBUTING.md`, a test-folder README, or lint
config conflicts with this skill, follow the project and say so in the report. Project rules live in
the project's docs. Cite those docs, not this skill, when a project rule is at stake.

Discover the project's version of each concern before judging it:

| To learn | Look at |
|---|---|
| Where tests live and how they are organised | `playwright.config.*` (`testDir`, projects), the test folder tree, existing specs |
| How tests run and authenticate | `playwright.config.*` (`storageState`, projects), `package.json` scripts, `Makefile` |
| How CI runs them | `.github/workflows/*`, `.gitlab-ci.yml`, other CI config |
| Guard, lint and tag scripts | `package.json` scripts, lint config, `scripts/` or `tools/` folders |
| Tag convention | tags on existing tests, the test-folder README |
| Folder rules (page objects, fixtures, support, test data) | every `README.md` under the test folder (glob for them; a new one may have landed) |
| Translations | i18n libraries in `package.json`, locale files, `t(` / `useTranslation` calls |
| API contracts and parsing | schema libraries (zod, ajv, io-ts, OpenAPI), contract files, a shared API client |
| Quarantine or known-issue convention | a register document; grep for `quarantine`, `known-issue`, `fixme` |
| Canonical examples | the README or contributing doc; the example files it names are the reference, and a change that disagrees with them is a finding |

If the repo has none of these (no folder READMEs, no guards, no contracts), the principles here still
apply. Findings that depend on a repo-specific rule do not apply, and you say so.

## Resolve the target

State the resolved file list in one line before reviewing. **Never review a file you have not read in
full.** A diff hunk misses the helper it depends on. Read what the target imports too: page objects,
fixtures, support helpers, test data. Most real findings are visible only there.

- **A path**: review that file.
- **A bare filename**: find it under the test folder. Two hits: ask which.
- **Nothing, or "my changes" / "this branch"**: the union of four sets. A new spec that is only staged,
  or still untracked, must be reviewed. Leaving those out lets an unreviewed file through.
  ```bash
  # Substitute <test-dir> with the test folder you discovered.
  base=$(git symbolic-ref --short refs/remotes/origin/HEAD)  # discover the default branch; do not assume master
  git diff --name-only "$base"...HEAD -- <test-dir>/        # committed on this branch
  git diff --name-only --cached -- <test-dir>/              # staged
  git diff --name-only -- <test-dir>/                       # unstaged
  git ls-files --others --exclude-standard -- <test-dir>/   # untracked
  ```
  If the symbolic ref is missing, ask the user for the base branch rather than guessing.

## Procedure

1. **Run the project's own checks** (lint, typecheck, guard scripts, tag checks) if it has them. Find
   them in the scripts and CI. Report their output separately from your findings. A check that scans only
   the staged list sees nothing during a review and passes vacuously, so run it over the whole suite or
   pass the resolved files explicitly. Never run a bulk `--fix` or rewrite mode during a review. A guard
   hard failure is a Critical finding; do not re-derive it by eye.
2. **Naming pass, first** (`references/naming.md`). Run it before the correctness hunt, especially when
   you wrote the code under review. Every name the diff introduces or renames.
3. **Scope check** (`references/checks.md` §0). A test-only change must not touch app code.
4. **Static scans and brittle-selector greps** (`references/checks.md` §1–2). Every hit is a finding until
   triaged.
5. **Structure checks** (`references/checks.md` §3–8): spec, page object, fixture and service, test data,
   DRY and single responsibility, programming patterns, comments.
6. **Judgment checks** (below), in the order listed.
7. **Write the report** (format below). Failure-message and skip-reason rules are in
   `references/failure-messages-and-skips.md`.

## Judgment checks (no grep catches these)

- **Naming.** The naming pass in step 2. Each name read cold; a name that needs its body to be understood
  is the finding.
- **Reuse first.** Before accepting an inline locator, mock, factory, literal or helper, check whether the
  project already owns it: page objects, fixtures, support, test data, i18n. An inline copy of something
  that exists is a finding, even when it passes. Remedy: reuse or extend the owner.
- **Assertion oracles.** The expected value must come from an independent source: test data, the seed the
  test wrote, a contract, or the feature's specification. A value read back from the app or service under
  test and asserted against that same app is a tautology: **Critical**, because the test cannot fail for
  the bug it exists to catch. Two operands derived from the same source are the same tautology.
- **Journey or area: does it mock or walk the real flow?** A test that stubs the seam it exists to prove
  has faked its purpose. Name the file for what it does, mocked component or real flow, and check that the
  name matches.
- **Red for the right reason.** For each assertion, name the defect it would catch. An assertion with no
  answer is decoration. Check that the setup creates the condition the assertion needs; otherwise the test
  passes trivially or fails for an unrelated reason.
- **Failure messages.** A message must state the facts (the diverging values and direction), not restate
  the rule. Details in `references/failure-messages-and-skips.md`.
- **UI copy (conditional: the project renders copy from translations).** Assertions on user-facing wording
  take their expected value from semantic state first (`role`, `aria-*`, a `data-state`-style hook), which
  is locale-proof. If the project has i18n, take expected text from the translation source, keyed by the
  active locale, check that the key exists and is the one the component renders, and check that any
  translation helper is not called with a hard-coded locale. A hand-typed literal
  is a finding even when it passes. If the project has no i18n, keep expected copy in one test-data module,
  not scattered across specs. Not findings: test IDs, slugs, state values, API enums, and copy genuinely
  absent from the app's translations, provided it is extracted once with a reason. Translation quality is
  out of scope; the test checks wiring.
- **Contracted response bodies (conditional: the project has schemas or a loose parser).** For every
  endpoint a test exercises, ask what validates the body. A loose or error-envelope parser validates
  nothing about the body. Body fields asserted with no schema behind them are **Critical**. Check the
  shared contracts before accepting a test-local schema. Details in `references/checks.md` §5b. Schema
  strictness itself belongs to `api-contract-testing`, if installed.

## Hard rules

1. **Report, never silently edit.** Apply a fix only when the user asks, one finding at a time, with the
   finding quoted.
2. **Quote `file:line` and the offending line.** "Looks fine" is not a finding. A finding whose evidence
   you cannot trace is a suspicion: verify it or drop it.
3. **Never weaken a test to make it green.** `fixme`, `skip`, narrowed assertions, relaxed schemas,
   soft-asserting a status, or reducing scope to silence a real failure is **Critical**. The narrow
   exception is a known defect tracked by a ticket named in the reason (see `failure-messages-and-skips.md`).
4. **App code is off-limits.** A change that touches app source, public assets, or anything outside the
   test folder is **Critical** unless the user explicitly authorised it. Quote the project's own rule on
   app-code changes. Route app findings to the team that owns the code. A confirmed app bug becomes a
   ticket, never a loosened assertion or a skip. Proposing a test hook in app code is a proposal, not an edit.
5. **Review the files, not the author's account.** Read the files yourself. A description from the agent or
   person who wrote the code is not evidence.

## Severity

- **Critical**: must fix before merge. Silenced failures, tautologies, manufactured green, missing `await`,
  app code touched, try/catch in a test body, unlabelled parked tests, duplicate primary IDs, guard hard failures.
- **Architectural debt**: fix in this PR or a follow-up. Brittle selectors, missing step wrapping, literals
  that belong in test data, debt markers without a ticket, most naming findings.
- **Optimization**: suggestion, not a blocker. Extraction opportunities, comment hygiene, predicate names, size nudges.
- **Naming** findings sit in their own section, with their severity word inline.

## Report format

Plain markdown. No emoji, no preamble, no summary paragraph. The list is the report. Use this format
unless the user names another.

**Sections**, in fixed order. Omit any section with no findings, **except `Naming`, which is always printed**:

```
Critical
Architectural debt
Optimization
Naming
```

- `Naming` with no findings prints exactly `- none — every name the diff introduces or renames read clean on its own.`
  A silent absence looks like a skipped pass.
- Each naming finding carries its severity as the first word after the dash. A naming finding appears only in
  `Naming`, and is counted only in the `Naming` tally.
- When **three or more non-naming findings share one theme** (for example `i18n`, `a11y`, `Determinism`,
  `Reuse`), give that theme its own section after `Naming`. Each finding lives in exactly one section.

**A finding:**

```
- <path>:<line> — <one lowercase sentence stating the defect, not the category>
<the offending code, verbatim, indented>
  - <evidence: the mechanism, naming the symbol (path:line-range) and quoting the code that does it>.
    <why that makes it true>. <canon cited by owner, quoted>.
  <the remedy as an imperative, naming the concrete helper, home, or symbol; give the alternative if there is one>
```

Group by file, ordered by how much the reader should care. Note redundancy with existing coverage when it
exists. `Optimization` may hold a keep-this note that names what is correct and worth copying.

**Final line**, always last, exactly one line. The `Naming` count is always present, even at zero:

```
6 Critical, 8 Architectural, 1 Optimization, 2 Naming across 1 file (2 Critical findings also implicate tests/support/grouping.ts).
```

**Worked example** (neutral paths; map them to the project's folders):

```
Critical

- tests/checkout/cart.spec.ts:87 — the assertion can never fail.
  expect(emptyGroups, `Groups with zero items: ${emptyGroups.join(', ')}`).toHaveLength(0);
  - groupByField (tests/support/grouping.ts:31-37) creates a group key only when it pushes an item into it, so a
    zero-length group cannot exist in its output. Checks §3 "oracles" applies. Line 61 already makes the real
    version of this check. Delete it, or reframe it against an independent list in the test-data folder.

Naming

- Architectural — tests/support/grouping.ts:31 — `groups` says its shape (a map) but not its subject.
  const groups = new Map<string, Item[]>();
  - Read on its own it could hold anything. Naming pass: "its shape or type, but not of what".
  Rename to the subject: `recordsByField`.

0 Critical, 0 Architectural, 0 Optimization, 1 Naming across 2 files.
```

## Checklist

- [ ] Project checks run; their output is reported separately from findings.
- [ ] Target resolved in one line; every file read in full, with the files it imports.
- [ ] Naming pass run first on every introduced or renamed name; `Naming` section printed.
- [ ] Static scans and brittle-selector greps run; every hit triaged.
- [ ] Test-only scope confirmed; no app code touched; no test weakened.
- [ ] Assertions: oracle independent, red for the right reason, hard or soft as appropriate, inside steps.
- [ ] Failure messages name the facts; skip and fixme reasons lead with the cause or a ticket.
- [ ] Every finding quotes `file:line` and the offending line, with traced evidence and a remedy.
- [ ] Final tally line last, with the `Naming` count.
