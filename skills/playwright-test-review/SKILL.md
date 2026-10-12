---
name: playwright-test-review
description: "Code review for Playwright/TypeScript tests under tests/e2e/ — checks POM purity, fixtures, repo conventions, assertions, and test-data centralization. Use before merging an e2e PR, auditing specs, or refactoring fixtures/pages. Produces a findings report, never silent edits."
---

# Playwright Test Review

> **Scope:** every file under `tests/e2e/` — specs, page objects, components, fixtures, services, schemas, support, helpers, test-data.
> **Load alongside:** `playwright-core`, `playwright-api`, `playwright-ui`. This skill *checks compliance* with those skills — it does not restate their rules. When in doubt about a rule's wording, the source skill wins.
> **Source of truth:** `tests/e2e/playwright.config.ts`, `fixtures/`, `services/`, `support/`, `test-data/`. Code wins over any example below.
>
> **Placeholders** — map each one to your own project before use:
> - `<frontend-dir>` / `<backend-dir>` — the front-end and back-end app folders that a test PR must not touch.
> - `<ticket-prefix>` — your issue tracker's key prefix, as in `<ticket-prefix>-1234`.
> - `<ci-scripts-dir>` — the folder that holds the repo's canon check scripts.
> - `<blocking-env-var>` — the env var that turns a report-only guard into a blocking one.
> - `<staging-secret-env>` / `<bypass-header>` — the staging bypass secret variable and the header that carries it.
> - `<domain-data>` — a per-domain test-data module name.
> - `<fixture-value>` / `<locale>` — a literal to match in a grep or code example.
> - `<area>`, `<feature>`, `<domain>`, `<Domain>`, `<Route>` — folder and file names in the examples; use your own.
> - `<ui-path-helper>` / `<api-path-helper>` — the project's utility functions that build locale-prefixed UI and API paths.
> - `<e2e-env-prefix>` — the prefix used for E2E environment variable names (e.g. `<e2e-env-prefix>_LOCALE`, `<e2e-env-prefix>_TARGET`).
> - `<api-client>` — the canonical API client class and its file in `services/` (e.g. `services/<api-client>.ts`).
> - `<parse-response-fn>` / `<parse-response-loose-fn>` — the project's response-parsing utilities: the strict and loose variants.
> - `<instrumented-page-fixture>` — the base fixture file that instruments the Playwright `page` object before other fixtures extend it.
> - `<api-fixtures-type>` / `<ui-fixtures-type>` — the TypeScript types that enumerate all API and UI fixture names.
> - `<encapsulated-fixture>` / `<tracker-fixture>` — the Pattern A (fully encapsulated) and Pattern B (cleanup-tracker) fixture examples from `fixtures/api-fixtures.ts`.

---

## Hard rules

1. **App code is off-limits in a test PR.** A diff that touches `<frontend-dir>/src/`, `<backend-dir>/app/`, `<frontend-dir>/public/`, or anything outside `tests/e2e/` is a Critical finding unless the user has explicitly authorized it. Quote the project's CLAUDE.md QA directive on app-code changes in the report.
2. **Never edit a test to manufacture green.** `test.fixme`, `test.skip`, narrowed assertions, schema relaxations, soft-asserting status codes, or scope reductions used to silence a real failure are Critical. The narrow exception is ticket-tracked findings (`test.fixme(true, '<AREA>-TYPE-NNN: server returns wrong status — LINEAR-1234')`).
3. **Never delegate the review to the agent that wrote the code.** Read the actual files. Quoting a diff line with a `file:line` reference is required; "looks fine" is not a finding.

---

## Review procedure (run in order)

### Step 1 — Scope the diff

```bash
git diff --name-only origin/master...HEAD -- tests/e2e/
git diff --name-only origin/master...HEAD -- ':!tests/e2e/'   # MUST be empty for a test-only PR
```

If the second command prints anything, that's the first finding.

### Step 2 — Static scans (forbidden patterns)

Run each grep across `tests/e2e/`. Every hit is a finding — record `file:line` and the quoted line.

| Grep | Finding type | Severity |
|---|---|---|
| `import\s*{[^}]*\btest\b[^}]*}\s*from\s*['"]@playwright/test['"]` in `specs/**` | Spec must import `test` from `fixtures/api-fixtures` or `fixtures/ui-fixtures`. **Type-only** imports — `import type { Route, Page } from '@playwright/test'` — are allowed | Critical |
| `waitForTimeout(` | Arbitrary sleep — replace with web-first assertion or `expect.poll` | Critical |
| `waitForLoadState\('networkidle'\)` | SSR applications never go idle — use a deterministic locator wait | Critical |
| `waitForLoadState\('load'\)` in `pages/**` or `components/**` | If genuinely needed (Astro hydration timing), comment **why** inline; otherwise replace with a deterministic locator wait | Architectural |
| `\.skip\(|\.fixme\(` — **triage by intent** (`playwright-core` §skip-vs-fixme). **Parked** (`.skip(true`, `.fixme(true`, `.fixme(<title>`, `describe.fixme`) with no `<ticket-prefix>-\d+` ticket in message or adjacent comment = silenced failure, Critical. **Guard** (`.skip(<condition>, …)`) needs a message stating *why this run can't cover it* (missing var/data/env); no ticket required — a guard with an empty/vague reason (`'flaky'`, `'skip'`) is a finding | Critical (parked, no ticket) / Architectural (guard, no why) |
| `new Promise\(\(resolve\) => setTimeout\(resolve` outside `services/<api-client>.ts` | Hand-rolled sleep — `<api-client>.sleep()` is the single canonical implementation | Architectural |
| `try\s*{[^}]*finally` in `specs/**` | Spec-level teardown — must live in a fixture | Critical |
| `expect\(` in `pages/**` or `components/**` **outside** an action-macro pre-gate | POMs may use `expect(...).toBeEnabled()` / `.toBeVisible()` as a pre-condition before an action, but **post-state assertions belong in specs only** (see Step 4) | Critical |
| `'/<locale>/` (a locale segment hard-coded in a string literal in specs or pages) | Locale baked into path — use `<ui-path-helper>(locale, …)` / `<api-path-helper>(locale, …)` from `support/constants/locales.ts` | Critical |
| `/api/\$\{this\.locale\}` or `\`/api/\$\{locale\}` in `services/**` | Service hand-rolls a locale-bound URL — must use `<api-path-helper>(this.locale, …)` (grep to find current offenders) | Architectural |
| `process\.env\.<e2e-env-prefix>_` outside `fixtures/`, `support/`, `test-data/`, or `playwright.config.ts` | Read the `locale` fixture or a TDM module, never `process.env` in spec/POM code | Architectural |
| `console\.log\(|console\.debug\(` in tracked files | Stray debug logging — use the project's test logger (e.g. from `support/mechanism/<logger-module>`) if logging is required | Architectural |
| `faker\.setLocale\(` | Removed in faker v8 — use `@faker-js/faker/locale/<x>` subimports | Critical |
| `as unknown as ` / `as any` | strict-mode bypass — fix the typing instead | Architectural |
| `\.click\(|\.fill\(|\.goto\(` without preceding `await` | Missing await on a Promise — race, will flake | Critical |

Quick combined command:

```bash
cd tests/e2e && grep -RnE \
  "import\s*\{[^}]*\btest\b[^}]*\}\s*from\s*['\"]@playwright/test['\"]|waitForTimeout\(|waitForLoadState\('networkidle'\)|faker\.setLocale|as (unknown as|any)|/api/\\\$\{(this\.)?locale\}" \
  specs pages components fixtures services support helpers test-data || true
```

### Step 2b — Selector & assertion brittleness (hard-reject) <!-- selector-hygiene-gate -->

`data-testid` is the test contract: tests target stable
`{area}-{element}-{id}` testids — NOT text, role-name, CSS class, or DOM position. Each pattern
below is a finding — **Critical** when the element has (or should have) a testid. If no scaffold
hook exists yet, the finding routes to **dev-frontend** to add the hook (the test author must NOT
guess a selector harder); a UI element with no testid is an incomplete scaffold.

- **Framework-internal class locator** — `.locator(".<framework-prefix>-…")` / framework-internal class names. Breaks
  on any framework bump; asserts nothing semantic.
- **Styling/color-class locator** — `.locator(".text-red-600, .text-danger-600, …")`. Targets
  *appearance* as if it were meaning; breaks on a design change. (Real brittle example: the union
  `.<framework-class>, [role="alert"], .text-red-600, .text-danger-600` — keep ONLY the
  semantic `[role="alert"]`, or a testid.)
- **Structural / positional CSS** — `>` child chains, `nth-child`, `:first`/`:last` inside a
  `.locator(...)`. Breaks on any DOM reshuffle.
- **Fuzzy copy-dependent name** — `getByRole("button", { name: /confirm|proceed|next/i })`. Couples
  the test to button copy / i18n; renaming or translating the label breaks it.
- **Positional `.first()` / `.last()`** on a `getByRole`/`getByText`/`locator` used as the action or
  assert target. DOM-order-dependent — a second matching node silently grabs the wrong one. Scope to
  a testid instead.
- **Hardcoded fixture magic-values** — `getByText(/<fixture-value>/i)`, or any
  `getByText`/`toHaveText` whose literal is a fixture attribute. Couples the test to ONE
  fixture record; a different fixture fails for the wrong reason. Derive the expected value
  from the SAME fixture/URL the test seeds, then assert *that*.
- **Vacuous / self-comparing assertion** — an `expect` whose two operands derive from the same source
  can never fail (e.g. an admin-config response asserted equal to a second-config response when
  both come from one backend call). Trace both operands to origin; shared source ⇒ Critical.

Combined grep (run in `tests/e2e/`):

```bash
grep -RnE "\.locator\(['\"][^'\"]*(\.(text|bg|border)-(red|danger|green|success)|>|nth-child|:first|:last)|getByRole\([^)]*name:\s*/[^/]+\||\.(first|last)\(\)|getByText\(/[^/]*[0-9]" specs pages components || true
```

Each hit is a finding unless it is a justified, testid-scoped exception carrying an inline comment.
The remedy to recommend (never silently edit) is `getByTestId('{area}-{element}-{id}')`; a missing
hook is a dev-frontend scaffold gap, not a test-author problem.

### Step 2c — Fixtures canon (`fixtures/**`) <!-- fixture-canon-gate -->

Canon: the `fixtures/` README under `tests/e2e/`; machine-enforced by
`<ci-scripts-dir>/check-fixture-canon.mjs` (wired into the CI gate's e2e lane).

**The core question for every `fixtures/` file: is any of this actually SUPPORT code — a helper,
Page/API plumbing, domain seeding/assertion, or static data that a fixture merely *calls* — living
inside the fixture file or authored inline in a fixture body?** If yes, it belongs in `support/`
(mechanism/domain/util/constants/setup) and must be imported, not defined here. The fixture keeps
only the `acquire → use() → teardown` wiring. The fixture-vs-support boundary + decision test is in
`playwright-core` §"Fixtures canon" — apply it: *would a test destructure it as an argument?* → it's
a fixture and may stay; *is it a function/class/data something imports?* → it's support in the wrong
place, a finding.

**Run the guard first** — `node <ci-scripts-dir>/check-fixture-canon.mjs` from repo root; every hard
finding it prints is a Critical review finding. Then eyeball what the guard can't judge:

- **Exports-only (hard).** A `fixtures/` file may export ONLY fixtures, the composed `test`/`expect`,
  and fixture-type declarations. Any `export function` / `export class` / `export default` / bare
  `export { helper }` (a non-`expect` named re-export without `from`) / exported data or schema is a
  finding — the helper/data/schema belongs in `support/` (or a POM in `pages/`) and is imported.
  Pass-through `export { x } from "…"` and `export *` are allowed.
- **Thin bodies (cohesion — reviewer call, guard is report-only).** A fixture body is *wiring*, not a
  place to author setup logic. Inline `addInitScript` implementations, route handlers with real
  logic, `page.on(...)` listener bundles, or a reusable mechanism inlined in a body → extract to a
  named `support/mechanism/` installer and call it. **But** a body that only acquires → `use()` →
  tears down (register/login/seed-then-redact) is exactly what a fixture is — do NOT flag that.
- **Composition.** Specs import from one surface (`ui-fixtures` / `api-fixtures`); the base `page`
  instrumentation lives in `<instrumented-page-fixture>.ts` (merged first), not inlined per module. A
  moved fixture must not change a spec's import line or a destructured fixture name.
- **Option convention.** Run/CI-wide knobs (`<e2e-locale>`, `<e2e-target>`) are env vars; per-describe
  behavioural overrides use the `[default, { option: true }]` pattern via `test.use()`.
- **Naming.** `*-fixtures.ts` (concern bundle) or `<instrumented-page-fixture>.ts`; kebab-case; no vague
  `utils`/`helpers`/`misc`/`index`.

### Step 2d — Specs canon (`specs/**`) <!-- specs-canon-gate -->

Canon: the `specs/` README under `tests/e2e/`; machine-enforced by
`<ci-scripts-dir>/check-specs-canon.mjs` (wired into the CI gate's e2e lane; report-only until the
pending refactor lands, then blocking via `<blocking-env-var>=1`).

**The core question for every spec: is any of this NOT scenario-structure-or-assertion — a locator,
a data factory, a route mock, an API call, an expected UI string, a hardcoded locale — that already
exists (or belongs) in `pages/`/`fixtures/`/`support/`/`test-data/`/`<frontend-dir>/src/i18n`?** If yes it is a
finding: the spec is building in isolation instead of reusing. **Reuse-first is the #1 rule** —
before anything is authored in a spec it must be checked against the existing framework code and
reused/extended; new code goes to its proper home, never inline. This is the root cause the canon
fixes; treat an inline mock/factory/locator/string that duplicates framework capability as
Architectural debt even when the test passes.

**Run the guard first** — `node <ci-scripts-dir>/check-specs-canon.mjs` from repo root; every hard finding
is a review finding (Critical for the hard rules below, Architectural debt for report-only smells).
Then eyeball what the guard can't judge — that the extraction actually *reused* an existing
POM/helper/data rather than creating a near-duplicate.

- **Extraction destinations (hard).** `page.route` mock → `support/mocks/<area>/`; data factory / seed IDs
  → `test-data/` or `support/domain/<area>/`; UI string → app i18n reader (gap literals → `support/`/`test-data/`);
  API call + `Bearer` → the api fixture; `[data-testid]`/`[data-action]` locator → a POM getter; hardcoded
  locale → the `locale` fixture. Any of these inline in a spec is a finding.
- **Assertion oracles (hard).** Computed values (prices, totals, derived fields) must be derived independently by the
  test — a spec that reads a total from the app/service and asserts the app displays it is a Critical
  tautology finding. UI text asserted against a hand-typed English literal (vs semantic state or the
  app's i18n) is a finding.
- **Composed test import (hard).** The spec imports `test`/`expect` from `fixtures/`, never raw
  `@playwright/test` (raw import bypasses the instrumented page + prod-write-guard).
- **Structure (hard).** No spec-level `try/finally` teardown; no cross-test mutable module state; one
  behaviour per `test`.
- **Placement & naming.** One-level tab folder when a prefix cluster is large; filename fully-qualified
  and self-describing (`<area>-<feature>-<action>.spec.ts`, not `<area>.spec.ts`).
- **A11y.** axe/keyboard/ARIA coverage lives in a dedicated `*-a11y.spec.ts` tagged `@a11y` (not `@axe`)
  using the shared ruleset helper — not inlined in a functional spec.

### Step 3 — Spec-level checks (`specs/**/*.spec.ts`)

For each modified spec, verify:

- **Tier tag present.** Every `test(...)` (or its enclosing `describe`) carries exactly one of `@smoke`, `@happy-path`, `@regression`. `@smoke + @happy-path` is forbidden. Tags use array syntax — `{ tag: ['@smoke', '@regression'] }`, never `'@smoke, @regression'`.
- **Surface tag at describe.** `@api` for API specs, `@ui` for UI specs, set on the outer `describe`. Concrete grep:
  ```bash
  for f in $(find tests/e2e/specs/ui -name "*.spec.ts"); do grep -q "'@ui'" "$f" || echo "$f missing @ui"; done
  for f in $(find tests/e2e/specs/api -name "*.spec.ts"); do grep -q "'@api'" "$f" || echo "$f missing @api"; done
  ```
- **Module-level `let` requires serial mode.** Any spec that declares cross-test mutable state at the module top (`let token: string | null = null;` outside any `test`/`describe`) **must** also declare `test.describe.configure({ mode: 'serial' });` in the same file — otherwise `fullyParallel` will randomize test order and the dependent test will see `null`. Grep: `grep -RnE "^let [a-zA-Z]+.*=.*null;" tests/e2e/specs` then check each hit's file for `describe.configure.*serial`. Critical if mismatched.
- **`test.step()` coverage.** Every `expect(...)` lives inside an `await test.step(title, …)`. Step titles use the `Expected: X, Actual: ${actual}` form for value/state checks (`playwright-core` §test.step).
- **No bare assertions.** `expect()` directly inside a `test(...)` body (not wrapped in a step) is a finding.
- **Soft vs hard split.** Status-code gates, navigation-completion gates, and fixture preconditions are hard `expect()`. Multiple independent fields of a single response/component use `expect.soft()` with a descriptive label. Soft-asserting status then calling `.json()` is a Critical finding (`playwright-core` §soft assertions).
- **Null-guard before `body!.field`.** `body` from `<parse-response-fn>` is `T | null`. `expect(body, …).not.toBeNull();` must precede any `body!.…` deref.
- **Dynamic test data.** Resources created in the test must use `faker` or `crypto.randomUUID()`, never static identifiers (collides under `fullyParallel`).
- **No `try/finally` for cleanup.** Teardown is fixture territory only.
- **Test ID lives in the tag, not the title.** The stable trace handle is the tag
  (`@<AREA>-TYPE-NNN`), which the tag gate keys on — the title itself is behaviour-first
  plain language (see the naming gate below). A trace ID or ticket ID carried *as the title
  prefix* instead of a tag is a finding.
- **Exactly one primary `@AREA-TYPE-NNN` per test** (`playwright-core` §"Canonical test ID").
  Two primary IDs on one test's tag array (`… '@<AREA>-UI-001', '@<AREA>-UI-002' …`), or two `@…-AXE-NNN`,
  is a finding — the extra ID is dead weight and collides with the test that legitimately owns it
  (the pre-commit gate reports it as `duplicate-primary-id` / `duplicate-axe-id`). An AXE ID on a
  test whose body no longer runs axe-core, or a missing AXE ID on one that does, is also a finding.
  Critical.

### Step 3b — Test & assertion naming (plain-language, behaviour-first) <!-- naming-gate -->

The canonical rules live in `playwright-core` §"Test titles" and §"Step title format". This
gate enforces them. A title/step that reads as implementation-only — no subject, no outcome,
jargon-only, or a ticket/step-number in the title — is an **Architectural debt** finding
(**Critical** when it is actively misleading, e.g. a title that names the wrong endpoint).

Test-title findings (each is a finding — quote `file:line` + the offending title):

- **No subject / no outcome.** `returns 200 + FooSchema`, `responds within 2000 ms` — you can't
  tell *what* returns it or *why it matters*. Rewrite behaviour-first: *what loads/happens* and
  the *expected outcome*, with `(METHOD path → status / contract)` in trailing parens.
- **Jargon-only.** The title is schema class + verb + path with no domain words
  (`response body parses against the <resource>-derived schema`). Lead with domain language
  (*<resource> items load with all expected fields*); keep the schema/field/
  status detail inside `( … )`.
- **Mechanism instead of intent.** `… parses strictly` / `… is structurally valid` → say what
  that *means* (*loads with a complete, valid structure*).
- **Ticket ID or bare `Step N` in the title.** `<ticket-prefix>-1186-1 — …`, `Step 1 — …`. Tickets belong in
  a comment/tag; a journey step is named by its *purpose*, not a number.

Step-title (`test.step`) findings (`playwright-core` §"Two step kinds" + §"Assertion-step title format"):

- **Wrong kind.** An **action/setup step** (no `expect()` — navigate/click/fill/seed/intercept)
  must use an imperative verb, NOT `Verify` (`Verify the <page> is navigated to` is a finding →
  `Navigate to the <page>`). An **assertion step** (contains `expect()`) that does *not* start with
  `Verify` is a finding.
- **Retired `Assert:` / `Assert` prefix.** Assertion steps start with `Verify`. Any `Assert:`/
  `Assert ` step title is an Architectural-debt finding — rewrite to `Verify …`. Grep:
  `grep -RnE "test\.step\(\s*[\`'\"]Assert" specs`.
- **Missing the plain meaning.** `Verify body parses against FooSchema` states the mechanism —
  rewrite as `Verify the … data comes back in the expected shape`.
- **Value not interpolated** (already covered in `playwright-core` §step-title): a value/state
  check whose `Actual` isn't interpolated is a finding.

Quick grep for the worst offenders:

```bash
cd tests/e2e && grep -RnE "test\(\s*['\"](returns |responds |Step [0-9]|<ticket-prefix>-[0-9]|[A-Z]+-API-[0-9]+ )" specs || true
```

The remedy is always a rewrite to the behaviour-first template — never delete the title's
technical detail, move it into the trailing parentheses.

Variable-naming findings (canon: the `specs/` README under `tests/e2e/` §"Variable naming" —
reader-centric, team vocabulary; each is Architectural debt, **Critical** when the
name is actively misleading, i.e. it says one thing and holds another):

- **Generic state noun.** `const snapshot / start / states / result / data = …`
  holding captured state — the name must carry **subject + moment**
  (`groupStatesOnLoad`, `finishingGroupAfterReveal`). Grep:
  `grep -RnE "const (snapshot|start|states|result|data|res|tmp|info)\s*=" specs support`.
- **Invented domain term.** A concept the DOM/team already names, renamed by the
  author (`axis` for a `data-option-group` attribute → `optionGroup`). The team's word wins.
- **Mechanism name.** A variable named for the internal loop rather than its meaning
  for the test (`swept`/`notSwept` → `optionsToClick`/`optionsLeftUnclicked`).
- **Near-twins in one scope.** Two almost-identical names holding unrelated things
  (`reveal` + `revealed`).
- **Undefined abstraction.** An abstract term used without a defining docblock at its
  declaration (`transitions` — transition from what to what?).
- **Bare comparative or moment.** A name that gives the value's *position* but never
  its *subject*: `low`/`high`, `min`/`max`, `before`/`after`, `prev`/`next`,
  `first`/`last`, `counts`, `count`, `counted`, `total`, `reconciled`,
  `here`/`there`. **Carve-out:** `expected` / `actual` are the sanctioned names
  for an oracle-versus-observed pair (they match the `Expected: X, Actual: ${y}`
  step-title form Step 3 mandates) and are NOT findings on their own — flag them
  only when one scope holds several different expectations, where `expected`
  cannot say which. Cover the declaration and read `low <= high` — low
  *what*? Rename to `<subject><Position>`: `smallestBucketSizeSeen`,
  `bucketSizesBeforeRender`, `renderedChipCount`, `itemCountPerCategory`. The subject
  may be dropped **only** inside a one-line lambda whose argument is unambiguous
  (`(item) => item.id`). Grep:
  `grep -RnE "\b(const|let) (low|high|min|max|before|after|prev|next|first|last|counts|count|counted|total|reconciled|here|there|res)\b\s*[=:]" specs support pages components fixtures`.
- **Scope.** These rules bind `support/`, `pages/`, `components/` and `fixtures/`
  exactly as they bind `specs/` — a vague name in a shared helper is *worse*, every
  caller inherits it. Review the file's own declarations AND the names it
  destructures from the helpers it calls: `{ rendered, lowest, highest }` is a finding
  against the helper's return type, reported against the helper.

**Run the two greps above on every review, then read the remaining declarations by
eye.** This is judgment work no CI guard performs, and every hit is Architectural
debt at minimum — never filed under "Optimization, naming". A review that passes
`const counts = new Map()` or `const low = Math.min(…)` has not run Step 3b.


### Step 3c — Comment & header hygiene <!-- comment-gate -->

Enforces `playwright-core` §"File header comment", §"scenario lives in the title", and
§"Inline comments". Text rots when it duplicates something the code/tags already own.

- **Header traceability-code rot.** A file header carrying a `Traceability: F-09, C-32, …` code
  list or a `Tests: U-<AREA>1–U-<AREA>7` ID enumeration is an Architectural-debt finding — no gate reads
  those codes and the per-test `@AREA-TYPE-NNN` tag is the trace handle. The header should state
  surface + guarantee + prerequisites (+ optional single `Epic: <ticket-prefix>-####`). Grep:
  `grep -RnE "Traceability:|Tests:\s*U-|IDs:\s*[AU]-" specs`.
- **Doc block restates the title.** A `/** … */` above a `test()` that merely paraphrases the
  title is a finding — delete it. A comment is earned only by context the title can't hold
  (data precondition, red-by-design, *why it matters*). Optimization unless it's actively
  out of sync with the title (then Architectural).
- **Inline comment narrates the next line.** `// Click the first facet option` above
  `await facet.first().click()` states the WHAT — delete it. Keep only WHY comments (rationale,
  workaround, deliberate omission, ticket ref). Optimization; a cluster of narration comments in
  one spec is Architectural.

### Step 4 — Page Object / Component checks (`pages/**`, `components/**`)

> **Canon = the `pages/` README under `tests/e2e/`.** That file is the single source of truth for POM structure (the nine rules). Read it before reviewing a POM; the items below are its *review lens*, not a second copy. When it and this skill ever diverge, the README wins — update this skill to match, don't fork the rules.
>
> **What the gate already enforces:** `<ci-scripts-dir>/check-pom-canon.mjs` (wired into the CI gate's e2e lane) mechanically fails rules **1** (locators must be getters, not `readonly` fields), **2** (`constructor(private readonly page: Page)`, never `this.page = page`), and **8** (no first-party `[data-*]` CSS). So in review, spend your attention on the **judgment** rules the guard can't check: 3, 5, 7-naming, 9.

> **Support library (`support/**`) canon = the `support/` README under `tests/e2e/`.** `<ci-scripts-dir>/check-support-canon.mjs` (same e2e lane) enforces concern layering (`constants→util→mechanism→domain→setup`, imports flow down; sideways `domain/` only with a `// layer-ok: … TODO(<ticket-prefix>-…)` escape), kebab-case + non-vague filenames, and emits report-only cohesion smells. In review, spend attention on the **judgment** rules the guard can't check: is the file in the *lowest* fitting layer? does the filename predict its exports? are comments WHY-only? one cohesive role? Do NOT add a `helpers/` folder.

- **`expect()` is allowed only as an action-macro pre-gate, never as a post-state assertion** (rule 5). Legitimate: `await expect(this.loginSubmitButton).toBeEnabled();` before clicking, `await expect(this.panel).toBeVisible();` before filling. Forbidden: assertions on response shape, URL, computed values, totals — those belong in spec files. Triage: an `expect()` inside an `async <action>()` that gates the next interaction is OK; an `expect()` that *is* the verification is Critical.
- **No locale baking** — `goto(locale)` must use `<ui-path-helper>(locale, PAGE_SLUGS.…)`. Inline locale strings such as `/<locale>/` are Critical.
- **No `process.env.<e2e-env-prefix>_*` reads.** POMs take values via constructor or method args, or a fixture (grep `process.env.<e2e-env-prefix>_` under `pages/`). Architectural.
- **Locators are lazy getters** (rule 1) — `get x(): Locator { return this.page.getByTestId(…) }`, not `readonly x: Locator` assigned in the constructor. Getters get an explicit `: Locator` return type. Guard-enforced; flag any survivor.
- **Constructor binds `page` only** (rule 2) — `constructor(private readonly page: Page) {}`. No `this.page = page`, no locator assignment, no extra args beyond an `isMobile`/`opts` that makes the object genuinely vary. Guard-enforced.
- **`goto()` waits internally** (rule 4) — navigation awaits a public `waitFor…()` readiness method; a `goto()` that returns before hydration, or a spec forced to call a separate wait every time, is a finding.
- **Names carry the role; comments explain WHY not WHAT** (rule 7) — locator getters end in their element role (`quoteLink`, `reorderButton`, `…Card`, `…Modal`, `…Text`); a name like `quoteAction` that needs a comment to say "it's a link" is a finding. A comment that restates the name should be deleted.
- **Macro only when the interaction earns it** (rule 9) — a one-line `clickX()` wrapper around a trivial click is noise; conversely, a guarded/multi-step/reused interaction inlined across specs should become a macro. Specs may act on an exposed locator but must not derive a new locator from it.
- **No inheritance from a base POM class** that mutates Playwright's `test` or stores shared state. Independent classes are fine — `class LoginPage { constructor(private readonly page: Page) {…} }` is the pattern.
- **`getByTestId` first, then `getByRole` (no name); CSS is third-party-only** (rule 8, see `playwright-locators`). A first-party `page.locator('[data-*]')` or a structural CSS chain (`div > ul > li`) / XPath is a finding — the fix is a `data-testid` on the element (ticket the owning team), not a cleverer selector.
- **Scope to a panel/section locator** when the page shares its route with another POM or contains repeated form fields. `LoginPage` scopes everything to `[data-testid="login-form"]` because it shares `/login` with the register panel. Rule: any POM that shares a route MUST scope; pages that own their route SHOULD scope by section. New POMs without scoping when collision is possible are Architectural.
- **Magic timeout numerics in POMs.** Literal `timeout: 10_000` / `timeout: 15_000` sprinkled across `pages/` should reference a named constant in `support/`. Add the constant when there isn't one yet — `export const TIMEOUTS = { hydration: 15_000, slow: 30_000 } as const;`. Optimization for the first occurrence in a new POM; Architectural once a literal repeats across files.

### Step 5 — Test data / centralization checks (`test-data/**`, literals in specs)

The canonical TDM modules are: `test-data/env-config.json`, `test-data/test-users.ts`, the per-domain modules `test-data/<domain-data>.ts`, `support/constants/page-slugs.ts`, `support/constants/locales.ts`.

For each new literal in a spec or POM, ask: does it belong in one of these files?

- **Hardcoded resource IDs, slugs, domain-specific identifiers** → `test-data/<domain-data>.ts` or `support/constants/page-slugs.ts`. Critical if reused across ≥2 specs and not centralized.
- **Hardcoded emails or passwords** other than via `faker` → `test-data/test-users.ts` or `process.env`. Critical for passwords (must come from env).
- **Hardcoded addresses, postcodes, phone numbers** → `test-data/<domain-data>.ts`. Architectural.
- **Hardcoded environment URLs, base paths, slug strings** → `test-data/env-config.json` and resolved via `support/constants/locales.ts`. Critical.
- **Magic numbers and durations** in tests (timeouts, throttle windows, retry counts) → named constants in `support/util/` (see a named constants module there for the pattern). Architectural.
- **TDM exports must be immutable.** New `export const` in `test-data/` and `support/` must end in `as const` (or use `Readonly<>` / `readonly` arrays). Mutable exports silently leak state across tests in the same worker. Grep: `grep -RnE "^export const " tests/e2e/test-data tests/e2e/support | grep -vE "as const|Readonly|readonly"`. Architectural for new exports; pre-existing mutable exports are debt, not a blocker.

A single ad-hoc literal used in one place is fine; the rule is "once is a coincidence, twice is a constant, three times is a module".

### Step 6 — Fixture & Service checks (`fixtures/**`, `services/**`)

**Fixtures:**

- **`test.extend<T>` only.** No class inheritance for cross-test state. Base-page or base-test hierarchies are Critical.
- **Typed payload.** Every fixture has an entry in the `<api-fixtures-type>` / `<ui-fixtures-type>` type. No untyped fixtures.
- **I/O fixtures wrap setup/teardown in `await test.step('Fixture Setup: …')` / `'Fixture Teardown: …'`.** Without this, fixture failures show as opaque internals (`playwright-core` §fixture traceability). Trivial fixtures that only `new` a service class don't need step wrapping.
- **Pattern A vs Pattern B chosen correctly.** If the spec asserts the creation response, it must use the tracker fixture (`<tracker-fixture>.track(id)` immediately after obtaining the ID). Otherwise use the encapsulated fixture (`<encapsulated-fixture>`). See `fixtures/api-fixtures.ts` header doc.
- **Teardown is no-throw.** Fixture teardown must never throw on a best-effort cleanup path (it masks the real test failure). Pattern: `console.error(...)` instead of `expect(...)` in teardown. See teardown-only fixtures in `fixtures/api-fixtures.ts` for the pattern.
- **No `request.newContext()` without `<bypass-header>` injection** when `<staging-secret-env>` is set. `use.extraHTTPHeaders` does not propagate to manually-created contexts (`playwright-core` §staging bypass).

**Services:**

- **URLs built via `<api-path-helper>(this.locale, …)`, never `` `/api/${this.locale}/…` ``.** Hand-rolled URL templates skip the canonical helper and drift from production routing. Critical. (Same grep as Step 2.)
- **No service-level 429 retry, backoff, or sleep.** `services/<api-client>.ts` already implements the 429 retry policy (Retry-After aware) and the canonical `sleep`. Legacy per-service helpers (e.g. methods named for 429 retry / `private async wait(ms)`) are duplications that produce competing retry policies. Rule: all 429/backoff/sleep logic lives in `<api-client>`. Grep:
  ```bash
  grep -RnE "private async (wait|sleep)\(ms" tests/e2e/services
  # also grep for any project-specific 429 helper method names
  ```
  Architectural.
- **Hard-coded retry-delay arrays are a code smell.** A literal delay array (e.g. `[800, 1500, 2500]`) in a service or fixture means that code is doing its own 429 backoff — the retry policy already lives in `<api-client>`. The fix is to route the call through an `<api-client>` verb method (`get`/`post`/…) and delete the array, **not** to reference `<api-client>`'s internal delay constants: those are unexported module-scoped `const`s, private by design and not importable. Architectural.
- **Service classes own one domain.** A service > 300 lines or touching > 1 controller surface is doing two jobs — split.
- **Response shape consistency.** All service methods return `{ response: APIResponse, body: T | null, error?: … }` (the convention enforced by `<parse-response-fn>`). Any service that returns a bare `APIResponse` or a custom shape is a finding — it forces every caller to re-implement null-guarding.
- **`<parse-response-loose-fn>` is a debt marker (rule 5a).** A `<parse-response-loose-fn>(` in `services/` without a same-line `TODO(<ticket-prefix>-NNNN)` is Critical — the body is unmodelled and a field rename will not fail this parse. Grep:
  ```bash
  grep -Rn "<parse-response-loose-fn>(" tests/e2e/services
  ```

### Step 7 — DRY / Single-Responsibility pass

After the mechanical checks, scan for structural smells:

- **Duplicated setup code** across ≥2 specs in the same domain → extract a fixture (Pattern A if no response assertion needed, Pattern B otherwise).
- **Duplicated helper logic** that doesn't touch `page` / `request` → stateless function in the right `support/` layer (there is no `helpers/` folder; `support/` replaces it). Never pass `page` or `request` into a `support/` helper — that crosses the line into stateful territory and belongs in a POM, a service, or a fixture. Grep: `grep -RnE "(page|request)\s*:\s*(Page|APIRequestContext)\b" tests/e2e/support`. Critical for new code; Architectural debt for pre-existing offenders until extracted into POMs/services.
- **POM doing two jobs** (e.g., a `LoginPage` that also models the register tab) → split. SRP for POMs is "one route, or one cross-route widget".
- **Spec doing UI clicks to set state that an API call could seed.** Prefer the `request` context + a `Service` class. A UI test should not be clicking through authentication and earlier flows just to reach its target route — use an `<auth-session-fixture>` + a service call to seed state, then `page.goto(<ui-path-helper>(locale, '/<route>'))`.
- **A spec file >300 lines or with >10 tests** → suggest splitting by sub-domain, but only if there's a natural seam. Length alone is not a finding.
- **POM >250 lines** → probably modeling two routes; check whether it can split. Flag over-budget POMs for follow-up, don't block on pre-existing ones.
- **Service >300 lines** → probably modeling two domains; check the controller surface it wraps.

### Step 8 — General programming patterns (test-scoped)

Most SOLID-style concerns are already enforced by earlier steps in their test-specific form (SRP for POMs, composition over inheritance for fixtures, DI via `test.extend`, encapsulation via Pattern A/B). The patterns below catch smells those steps miss.

- **No branching in a test body.** `if` / `else` / `switch` / ternary-driven assertions inside a `test(...)` mean the test exercises multiple paths and the failure message can't tell you which one broke. Rule: one path per test. The narrow exceptions are early-return after `test.skip(...)` (e.g. `test.skip(!isStagingRun, …)` at the top) and `expect(body, …).not.toBeNull()` followed by `body!.…`. Loops are allowed only over a static `.forEach`/`for…of` of named cases, in which case prefer `test.describe.parallel.each` or N separate tests so each case reports independently. Architectural debt at minimum, Critical if the branching hides an unhandled path.
- **No `try/catch` in a test body.** Catching an error in a test silences the failure. The only legitimate `try` in `tests/e2e/` is `try/finally` in a *fixture* (where teardown must run after `use()` even if the test throws). `try/catch` in a spec file is Critical.
- **Law of Demeter on response/DOM chains.** A chain like `body!.data.<resource>[0].<nested>.<value>` is brittle and the failure message reads as a generic "Cannot read properties of undefined". Destructure or assign intermediate named variables: `const { items } = body!.data.<resource>; const firstTotal = items[0]?.<nested>?.<value>; expect(firstTotal, '<description>').toBe(…);`. Architectural debt when the chain ≥ 4 hops or appears in ≥ 2 assertions.
- **Immutability for TDM modules.** New objects in `test-data/` and `support/` must be `as const` (or `Readonly<>`/`readonly` arrays) so tests can't mutate them and silently affect later tests in the worker. Pattern: `export const PAGE_SLUGS = { <slug>: '/<path>' } as const;`. Architectural debt when a new TDM export is mutable.
- **YAGNI for fixtures, services, helpers, POM methods.** A service method, fixture, or page-object method with no caller is noise — it confuses the next author and rots silently. Run `grep -RE "<symbol>" tests/e2e/specs` for any export added in this diff; zero hits means delete it. Optimization unless the symbol claims to test a contract that isn't covered elsewhere, in which case escalate to Architectural debt.
- **Predicate naming.** Boolean variables and helpers read as questions: `isStagingRun`, `hasResults`, `canSubmit`, `shouldRedact`. Avoid neutral nouns (`status`, `state`) for booleans — they don't tell you which value means "true". Optimization.
- **Test name = failure message.** The first thing you see in CI is the test name, and a
  non-engineer should understand it. `'login'` is useless; `'returns 200 + AuthSchema'` is
  jargon-only; `'A valid email returns a generic success message (POST /auth/forgot-password →
  200)'` reads as the behaviour under test with the technical scope in parens. The stable trace
  ID goes in the **tag** (`@AUTH-API-101`), not the title. See the Step 3b naming gate — titles
  that don't describe behaviour in plain language are Architectural debt.

Quick grep for the structural ones:

```bash
cd tests/e2e && grep -RnE \
  "^\s*(if|switch)\s*\(|^\s*}\s*else\b|try\s*{" \
  specs || true
```

(The `try` hit will include legitimate fixture teardown — filter to `specs/` only.)

---

## Finding categories (use these exact labels in the report)

**Critical** — must fix before merge. App code touched, manufactured green, missing await, missing tier tag, missing `test.step`, locale baked in, soft-asserting a gating status, fixture importing `test` from `@playwright/test`, hardcoded credentials.

**Architectural debt** — should fix in this PR or a follow-up: structural CSS selectors, missing soft-assertion labels, literals that should live in `test-data/`, POMs without scoping locators, `console.log` left in tracked files, missing fixture step-wrapping on I/O.

**Optimization** — suggestion, not a blocker: UI flow that could be API-seeded, fixture extraction opportunities, naming, SRP nudges, comment hygiene.

---

## Output format

Plain markdown. No emoji. One section per category. Each finding has: severity inline, `file:line` reference, the offending line quoted in a code block, a one-sentence diagnosis, and a fix (a before/after only when the fix isn't obvious from the diagnosis).

```markdown
## Critical

- **`specs/api/auth/forgot-password.spec.ts:42`** — locale baked into path.
  ```ts
  await request.get('/<locale>/auth/forgot-password');
  ```
  Use `apiPath(locale, '/auth/forgot-password')` from `support/constants/locales.ts`. Inline locale strings break every other supported locale and ignore `E2E_LOCALE`.

## Architectural debt

- **`pages/<Route>Page.ts:88`** — structural CSS selector.
  ```ts
  this.submitBtn = page.locator('form > div:nth-child(3) > button');
  ```
  Replace with `page.getByTestId('<area>-submit')` — the component already exposes a `data-testid`.

## Optimization

- **`specs/ui/<area>/<feature>.spec.ts`** — clicks through `/login` and `/list` to reach `/<page-path>`. Replace with `authedSession` + `<resource>Service.seed(...)` to seed via API, then `page.goto(uiPath(locale, '/<page-path>'))`.
```

End with one line:

```
N Critical, M Architectural, K Optimization across F files.
```

No conclusion, no preamble, no "great work overall". The list is the report.

---

## Canonical references

Read these before flagging a pattern as wrong — they're the gold-standard examples.

| Pattern | File |
|---|---|
| API spec | `tests/e2e/specs/api/<area>/<feature>.spec.ts` |
| API spec with serial mode + custom fixtures | `tests/e2e/specs/api/<area>/<feature-with-serial-mode>.spec.ts` |
| Service class | `tests/e2e/services/<Domain>Service.ts` |
| Zod schemas | `tests/e2e/schemas/<domain>.schema.ts` |
| UI spec | `tests/e2e/specs/ui/<area>/<feature>.spec.ts` |
| POM | `tests/e2e/pages/<Route>Page.ts` |
| Pattern A fixture (encapsulated) | `<encapsulated-fixture>` in `fixtures/api-fixtures.ts` |
| Pattern B fixture (tracker) | `<tracker-fixture>` in `fixtures/api-fixtures.ts` |
| Centralized test data | `test-data/test-users.ts`, `support/constants/page-slugs.ts`, `support/constants/locales.ts` |
| Stateless helper | `support/util/<stateless-util>.ts`, `support/domain/<domain>/<helper>.ts` |
| Playwright config | `tests/e2e/playwright.config.ts` |

If the modified code disagrees with these references on a pattern, the reference wins and the modification is a finding.
