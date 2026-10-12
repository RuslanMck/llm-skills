# Check catalogue

The full set of review checks, by area. Each check: what it catches, why it matters, how to
spot it, and the severity. Read the section for the area you are reviewing. Greps are example
patterns: run them in the test folder you discovered, and adapt them to the project's names.

Severity words are defined in SKILL.md §Severity. A check marked **(conditional)** only applies
when the project has the thing it names; if it does not, skip the check and say so.

---

## 0. Scope

- **Test-only changes stay test-only (hard).** A test PR that touches app source, public assets,
  or anything outside the test folder is Critical unless the user explicitly authorised it.
  Discover the app folders from the repo layout, then run:
  ```bash
  base=$(git symbolic-ref --short refs/remotes/origin/HEAD)
  git diff --name-only "$base"...HEAD -- ':!<test-dir>/'   # must be empty for a test-only change
  ```
  Substitute `<test-dir>` with the test folder you discovered. A non-empty result is the first finding.
  If the project states a rule on app-code changes (its `CLAUDE.md` or contributing doc), quote it in the report.
  If it states none, say so and rest the finding on the test-only scope.
- **Adding a test hook to app code is a proposal.** A missing `data-testid` or accessible name is
  fixed by the owning team. The review proposes it; it does not edit it.

---

## 1. Static scans

Every hit is a finding. Record `file:line` and the quoted line, then triage: a justified exception
carries an inline comment that says why.

| Pattern (example) | Finding | Severity |
|---|---|---|
| `waitForTimeout\(` | Arbitrary sleep. Replace with a web-first assertion or a polling assertion (see `playwright-waiting`, if installed). | Critical |
| `waitForLoadState\('networkidle'\)` | Not a readiness signal. Streaming, polling or server-rendered pages may never go idle. Wait on a deterministic locator instead. Playwright's docs also discourage it. | Critical |
| `waitForLoadState\('load'\)` in page objects or components (conditional: the project has page objects) | If genuinely needed (for example framework hydration timing), the reason must be a comment at the call. Otherwise replace with a deterministic locator wait. | Architectural |
| `try\s*\{[^}]*finally` in spec files | Spec-level teardown. Teardown belongs in a fixture. | Critical |
| `try\s*\{` in a test body (a `catch`) | Catching an error in a test silences the failure. The only legitimate `try` is `try/finally` inside a fixture. | Critical |
| `expect\(` in page objects or components, outside a pre-gate (conditional: the project has page objects) | Post-state assertions belong in specs. See §4. | Critical |
| `faker\.setLocale\(` | Removed in faker v8. Use the locale subpath imports (e.g. `@faker-js/faker/locale/<x>`). | Critical |
| `new Promise\(\(resolve\) => setTimeout\(resolve` outside the project's shared sleep helper (conditional: only if the project has one) | Hand-rolled sleep. Use the one shared implementation. | Architectural |
| `process\.env\.` outside the module the project designates for config (e.g. a config, fixture or test-data module) | Read config through one module or a fixture, not in spec or page-object code. | Architectural |
| `console\.(log\|debug)\(` in tracked files | Stray debug logging. Use the project's logger if it has one. | Architectural |
| `as unknown as \|as any` | Strict-mode bypass. Fix the typing. | Architectural |
| `^\s*[A-Za-z_.()]+\.(click\|fill\|goto)\(` | A Promise-returning call with no `await`: a race that flakes. | Critical |
| `['"\`]/[a-z]{2}(-[A-Z]{2})?/` (conditional: multi-locale apps only) | A locale segment baked into a path. See `multi-locale-testing`, if installed. | Critical |

Combined command (example; adapt the alternatives to the project):

```bash
# Substitute <test-dir> with the test folder you discovered.
cd <test-dir> && grep -RnE \
  "waitForTimeout\(|waitForLoadState\('networkidle'\)|faker\.setLocale|as (unknown as|any)|^\s*[A-Za-z_.()]+\.(click|fill|goto)\(" \
  . || true
```

**`.skip(` and `.fixme(` triage.** Grep `\.skip\(|\.fixme\(` and triage by intent (§2 of
`failure-messages-and-skips.md`):

- A **parked** skip (unconditional, or `fixme` with a `true` condition) with no ticket or cause
  in its reason is a silenced failure. **Critical.**
- A **guard** (`skip(<condition>, reason)`) must say why this run cannot cover the test (missing
  variable, data or environment). A vague reason (`'flaky'`, `'skip'`) is an **Architectural** finding.

---

## 2. Selector and assertion brittleness (browser tests only; for an API-only suite, skip this section and say so)

Locator preference (upstream guidance, and the order to recommend when fixing a finding):

1. **Semantic and user-facing:** `getByRole` with an exact accessible name, `getByLabel`,
   `getByPlaceholder`, `getByText` (exact), `getByAltText`, `getByTitle`.
2. **Test IDs** (`getByTestId`) when the element has no stable user-facing handle. Use the project's
   attribute name.
3. **CSS or XPath** last, and only for third-party markup that offers nothing better.

Upstream guidance does not rank test IDs above role names. A stable, exact role-plus-name locator is a
good locator, and it comes first.

Each pattern below is a finding, tiered by one rule. **Critical** when a stable semantic locator (role plus
accessible name, or a label) or a test ID already exists for that element and the test ignored it. **Architectural**
when no stable handle exists yet; then propose the hook to the team that owns the component. The test author
must not guess a harder selector.

- **Framework-internal class locator.** `.locator('.<framework-prefix>-…')`. Breaks on any upgrade
  and asserts nothing semantic.
- **Styling or colour class locator.** `.locator('.text-red-600, .text-danger-600, …')`. Targets
  appearance as if it were meaning. Keep only the semantic part of a union such as
  `.<framework-class>, [role="alert"], .text-red-600` (keep `[role="alert"]`, or a test ID).
- **Structural or positional CSS.** `>` child chains, `nth-child`, `:first`, `:last` inside
  `.locator(...)`. Breaks on any DOM reshuffle.
- **Fuzzy copy-dependent name.** `getByRole('button', { name: /confirm|proceed|next/i })`. Couples the
  test to button copy and translations. Use an exact name, or a test ID.
- **Positional `.first()` / `.last()`** as the action or assertion target. A second match silently
  grabs the wrong node. Scope to a test ID or a named container.
- **Hardcoded fixture magic values.** `getByText(/<fixture-value>/i)`, or a `getByText` / `toHaveText`
  literal that is an attribute of one seeded record. A different record fails for the wrong reason.
  Derive the expected value from the same fixture the test seeds, then assert that. Assertion coupling rather than a locator: **Architectural**.

Combined grep (example):

```bash
# Substitute <test-dir> with the test folder you discovered.
grep -RnE "\.locator\(['\"][^'\"]*(\.(text|bg|border)-(red|danger|green|success)|>|nth-child|:first|:last)|getByRole\([^)]*name:\s*/[^/]+\||\.(first|last)\(\)|getByText\(/[^/]*[0-9]" <test-dir> || true
```

Each hit is a finding unless it is a justified, test-ID-scoped exception with an inline comment.

---

## 3. Spec checks

For each modified spec:

- **Tier and surface tags (conditional: the project tags tests by tier or surface).** Every test, or
  its enclosing `describe`, carries the required tag(s) in the project's syntax, and no forbidden
  combinations. Discover the tag names from existing specs and the test-folder README, then grep:
  ```bash
  # Substitute <test-dir> with the test folder you discovered. Tag names are examples.
  for f in $(find <test-dir> -name "*.spec.ts"); do grep -q "@ui" "$f" || echo "$f has no @ui tag"; done
  ```
  Missing tier tag where CI selects by tag: **Critical**. Otherwise **Architectural**.
  Use the framework's array form for tags (Playwright: `{ tag: ['@a', '@b'] }`). A single comma-joined string is
  one tag, so grep filters miss it: **Architectural**.
- **Trace ID in the tag, not the title (conditional: the project has a test-ID scheme).** The stable
  trace handle lives in the tag. A trace or ticket ID used as a title prefix is a finding. Exactly one
  primary ID per test. Two primary IDs on one test is a **Critical** finding, because the duplicate
  collides with the test that owns the ID. An accessibility ID on a test that no longer runs the
  accessibility check, or a missing one on a test that does, is a finding.
- **Module-level mutable state needs serial mode.** A `let` at module top that tests share is a
  dependency between tests. Upstream guidance: each test sets up its own state, and tests do not
  depend on order. If shared state is unavoidable, the same file must declare serial execution
  (`test.describe.configure({ mode: 'serial' })` in Playwright). Mismatch: **Critical**.
  Discovery:
  ```bash
  # Substitute <test-dir> with the test folder you discovered.
  grep -rnE "^let [A-Za-z_]+" <test-dir> --include="*.spec.ts"
  ```
  Then check each hit's file for the serial declaration.
- **Expect grouping in steps (conditional: the project's convention requires steps).** Where the project's
  README, CLAUDE.md or a lint rule requires `test.step`, a bare `expect` directly in a test body is **Critical**.
  Otherwise it is **Optimization**: suggest steps for readable reports. Playwright does not require steps.
  Step-title format: see `naming.md`.
- **Soft versus hard assertions.** Gating checks (status codes, navigation completion, fixture
  preconditions) are hard. Several independent fields of one response or component are soft, each
  with a descriptive label. Soft-asserting a status and then reading the body is **Critical**: the
  body read runs on a response that already failed.
- **Null guard before dereference (conditional: the test reads a parsed body).** A parsed body can be null. Assert it is not null before any
  `body!.field`. Missing guard: **Architectural**.
- **Dynamic test data.** Records the test creates need unique identifiers (generated IDs, random
  suffixes). A static identifier collides under parallel runs. **Architectural**; **Critical** when
  it already collides.
- **One behaviour per test, no cross-test state.** A test that checks two unrelated behaviours fails
  in a way that hides the second. Split it.
- **Placement and naming (conditional: the project has a folder layout rule).** Filename predicts
  what the spec covers (`<area>-<feature>-<action>.spec.ts` as an example, not a rule). When a prefix
  cluster is large, group it in one folder level. **Optimization**.
- **Accessibility checks (conditional: the project runs an accessibility scanner).** Scanner runs
  live in a dedicated, tagged file that uses the shared ruleset helper, not inline in a functional
  spec. **Architectural**.

---

## 4. Page object and component checks

Canon: the project's page-object README, if one exists. Its rules win. If the project has a
machine guard for page objects, run it first. Its hard findings are Critical.

Apply these whether or not a canon exists. Each is conditional on the project using page objects
(component classes wrapping locators for a page or widget):

- **Assertions in page objects are pre-gates only (hard).** `await expect(x).toBeEnabled()` before an
  action is fine. An assertion that *is* the verification (response shape, URL, computed value, totals)
  belongs in a spec. An `expect` inside an action that gates the next interaction is fine; one that
  is the verification is **Critical**.
- **No environment reads in page objects.** Values come from the constructor, method arguments, or a
  fixture. **Architectural.**
- **Locators are lazy getters with explicit return types** (when the project's canon says so). A
  locator stored in a field assigned during construction goes stale and hides the lookup. **Architectural.**
- **The constructor binds the page and nothing else** (when the canon says so). Extra constructor
  work makes the object vary by hidden state. **Architectural.**
- **Navigation waits for readiness internally.** A `goto()` that returns before the page is ready, or
  a spec that must call a separate wait every time, is a finding. **Architectural.**
- **Locator names end in the element's role.** Names like `quoteLink`, `reorderButton`, `…Card`,
  `…Modal`. A name that needs a comment to say what it is gets renamed. See `naming.md`.
- **A macro only when the interaction earns it.** A one-line wrapper around a trivial click is noise.
  A guarded, multi-step or repeated interaction inlined in several specs should become a macro. **Optimization.**
- **No inheritance from a shared base that mutates the test runner or stores state.** Independent
  classes composed where needed. **Critical** for a base that holds cross-test state.
- **Scope to a section when the route is shared.** A page object that shares a route with another
  object scopes its locators to its own container. New objects that skip scoping when collision is
  possible are **Architectural**.
- **Specs act on exposed locators, never derive new ones.** A spec may act on a locator a page object exposes,
  but must not build a new locator from it (for example chaining off the getter). That couples the spec to the
  page object's DOM. Remedy: add a getter on the page object. **Architectural.**
- **Magic timeouts.** Literal timeouts in page objects should name a constant in one shared constants module.
  **Optimization** for a first occurrence; **Architectural** once a literal repeats across files.
- **Size.** A page object over about 250 lines may model two routes. Check whether it can split.
  Flag for follow-up; do not block on pre-existing ones.

---

## 5. Fixtures and services

### 5a. Fixtures (conditional: the project defines fixtures, for example Playwright `test.extend`)

- **Compose, don't inherit (hard).** Shared state goes through fixtures, not class hierarchies. A base
  page or base test hierarchy is **Critical**.
- **Typed.** Every fixture has an entry in the project's fixture type. No untyped fixtures.
- **Fixture setup and teardown are named steps.** Wrap I/O fixture setup and teardown in named steps
  (`'Fixture Setup: …'` / `'Fixture Teardown: …'` as examples), so a fixture failure shows up as a
  step instead of opaque internals. Trivial fixtures that only construct an object need no wrapping.
  Missing: **Architectural**.
- **Choose the right fixture pattern (conditional: the project splits fixtures this way).** If a spec asserts the response that creates a resource, the
  resource is tracked for cleanup right after its ID is obtained, so cleanup survives an assertion
  failure. Otherwise use an encapsulated fixture that owns acquire, use and teardown itself.
- **Teardown never throws.** A throwing teardown masks the real failure. Log instead of asserting
  in teardown. **Architectural**.
- **Fixture files export fixtures and types only (conditional: the project has this rule).** A
  fixture module exports fixtures, the composed test and expect, and fixture types. Helper functions,
  classes and data go to the support folder and are imported. Re-exports with `from` are fine.
  Exported helper in a fixture file: **Critical** (per the project's rule).
- **Thin bodies.** A fixture body is wiring: acquire, `use()`, teardown. An inline init-script
  implementation, route handler with real logic, or listener bundle is mechanism. Extract it to a
  named installer in the support folder and call it. A body that only acquires, uses and tears down
  is correct; do not flag it.
- **Composition.** Specs import from one surface (the composed test module). Base instrumentation is
  merged first, not repeated per module. A moved fixture must not change a spec's import line or a
  destructured fixture name.
- **Option convention (conditional: the project uses fixture options).** Run-wide knobs come from
  environment variables. Per-describe overrides use the fixture-options pattern.
- **Composed test import (conditional: the project wraps the runner's `test`).** Specs import `test`
  and `expect` from the composed module. A raw runner import bypasses instrumentation and any
  write guard. Type-only imports from the runner are fine. Raw import: **Critical**.
- **Manually created request contexts need the environment's required headers (conditional: the
  environment requires a bypass or auth header).** Default headers configured on a test project do not
  propagate to a context created by hand. Such a context must inject the header itself, or use the
  project's client. **Critical** when a required header is missing and the target rejects the request.
- **Fixture file naming.** Kebab-case, self-describing. No vague `utils`, `helpers`, `misc` or `index`.
- **Fixture or support?** Decision test: would a test destructure it as an argument? Then it is a
  fixture, and it may stay. Is it a function, class or data that something imports? Then it is support
  code in the wrong place: a finding.

### 5b. Services and the central API client (conditional: the project has a shared client or parser)

- **URLs come from the path helper.** Build URLs with the project's path helper, not hand-written
  template strings. Hand-rolled URLs drift from routing. **Critical** when the URL is locale-bound in a
  multi-locale app; **Architectural** otherwise.
- **One retry and backoff policy.** Retries, backoff and sleeps live in the central client. A per-service
  retry or sleep method (for example `private async wait(ms)`, or a 429 handler) creates a competing
  policy. Discover names by searching the services folder:
  ```bash
  # Substitute <test-dir> with the test folder you discovered.
  grep -RnE "private async (wait|sleep)\(" <test-dir>
  ```
  **Architectural.**
- **No literal retry-delay arrays.** A delay array in a service or fixture is hand-rolled backoff.
  Route the call through the client's verb methods and delete the array. Do not reference the
  client's private delay constants; they are not importable by design. **Architectural.**
- **Services own one domain.** Over about 300 lines, or touching more than one controller surface,
  means two jobs. Split. **Architectural.**
- **Response shape (conditional: the project has a response wrapper convention).** Service methods
  return the project's standard shape (for example `{ response, body, error }`). A bare response or a
  custom shape forces every caller to re-implement null guards. **Architectural.**
- **Contracts before local schemas.** Before accepting a test-local schema as correct, check the shared
  contracts folder (if the project has one). A canonical contract may already cover the endpoint under
  another name. A local duplicate of a contracted endpoint is worse than no schema, because both look
  authoritative. Go to `api-contract-testing`, if installed, for schema strictness.
- **Loose parsing is a debt marker (conditional: the project has a loose parse variant).** A loose parse
  validates only the error envelope, not the body. Body fields asserted against it pin whatever the
  endpoint returned on the day the test was written. A loose parse without a marker naming the ticket
  or owner that will model it is **Critical**. With a marker, it is **Architectural**. Grep for the
  loose parser's name in the services folder.

---

## 6. Test data

Discover the project's canonical data modules from the test-folder README (for example a per-domain
module, a constants module, an environment config file). Then, for each new literal in a spec or page
object, ask: does it belong in one of those?

- **Reused identifiers, slugs, domain values** belong in a test-data or constants module. If the project has
  one, the value goes there; if not, keep it in one module and say so.
  **Critical** when the project has such a module and a value reused across two or more specs bypasses
  it; **Architectural** when the project has none. Once is a coincidence.
  Twice is a constant. Three times is a module.
- **Credentials.** Passwords come from environment variables or a secrets mechanism, never literals.
  **Critical**. Emails come from a generator, or from a test-user module if the project has one.
- **Addresses, postcodes, phone numbers.** If the project has a test-data module, they go there; if not,
  keep them in one constants module and say so. **Architectural.**
- **Environment URLs, base paths, slug strings.** If the project has environment config or a path helper,
  a hardcoded environment URL is **Critical**, and the value goes there. If not, the configured base URL is
  the reference, and a hardcoded full URL is **Architectural**.
- **Magic numbers and durations** (timeouts, throttle windows, retry counts) become named constants.
  **Architectural.**
- **Exports are immutable.** New exports in test-data and support modules end in `as const`, or use
  `Readonly<>` or `readonly` arrays. A mutable export leaks state across tests that share a worker.
  Discovery:
  ```bash
  # Substitute <test-dir> with the test folder you discovered.
  grep -RnE "^export const " <test-dir> | grep -vE "as const|Readonly|readonly"
  ```
  New mutable exports: **Architectural**. Pre-existing ones are debt, not a blocker.

---

## 7. DRY and single responsibility

- **Duplicated setup across two or more specs in one domain** becomes a fixture if the project has fixtures,
  or a shared helper if not (or if no resource is created). **Architectural.**
- **Duplicated helper logic that touches no page or request** becomes a stateless function. If the project has
  a support or helper folder, put it in the fitting place there, lowest layer first (constants, utilities,
  mechanism, domain, setup). If not, a plain module next to the specs.
  **Optimization** on first duplicate, **Architectural** on the second.
- **Support layers and folders.** If the project layers its support code (constants, utilities, mechanism,
  domain, setup), a file lives in the lowest layer that fits its role, and imports flow downward only.
  One cohesive role per file. Comments say why, not what. Do not add a catch-all folder such as
  `helpers`, `utils` or `misc`; a new file's name predicts its contents. **Architectural.**
- **Helpers never take a page or request (hard).** The rule applies to any helper module, wherever it lives.
  Passing a browser page or API request context into a helper makes it stateful; that belongs in a page object,
  a service or a fixture. Discovery (Playwright types as the example):
  ```bash
  # Substitute <test-dir> with the test folder you discovered.
  grep -RnE "(page|request)\s*:\s*(Page|APIRequestContext)\b" <test-dir>
  ```
  **Critical** for new code; **Architectural** for pre-existing offenders until extracted.
- **A page object doing two jobs (conditional: the project has page objects)** (for example a login object that also models the registration tab)
  splits. One route, or one cross-route widget, per object. **Architectural.**
- **UI clicks used to set state an API call could seed (conditional: the project has an API client or service).** A test that clicks through authentication and
  earlier flows just to reach its target should seed through a service call and navigate directly.
  **Optimization.**
- **Size.** A spec over about 300 lines or with over 10 tests splits only along a natural seam. Length
  alone is not a finding. A service over about 300 lines is probably two domains.

---

## 8. General programming patterns (test-scoped)

Earlier sections already cover SRP and composition in their test-specific form. These catch the rest.

- **No branching in a test body (hard).** `if`, `else`, `switch`, or a ternary that decides which
  assertion runs means the test covers several paths, and the failure cannot say which one broke.
  One path per test. Narrow exceptions: an early return after a conditional skip at the top, and a
  non-null guard followed by a dereference. Loops are allowed only over a static list of named cases;
  prefer parameterised tests, or separate tests, so each case reports on its own. **Architectural** at
  minimum; **Critical** when the branch hides an unhandled path.
- **No try/catch in a test body.** Catching an error silences the failure. **Critical.** `try/finally`
  is legitimate only inside a fixture (or the project's equivalent teardown mechanism), where teardown must run after `use()` even if the test throws.
- **Law of Demeter on response and DOM chains.** A chain like `body!.data.items[0].nested.value` is
  brittle, and its failure reads as "Cannot read properties of undefined". Destructure intermediate
  named values, then assert on the named value with a description. **Architectural** when the chain
  has four or more hops, or appears in two or more assertions.
- **Immutability of shared data.** See §6, exports are immutable.
- **YAGNI for fixtures, services, helpers and page-object methods.** An export with no caller is noise
  that rots. Grep the test folder for each symbol the diff adds. Zero hits means delete it.
  **Optimization**, or **Architectural** when the symbol claims to test a contract nothing else covers.
- **Predicate naming.** Boolean variables and helpers read as questions (`isEmptyCart`, `hasResults`,
  `canSubmit`). Avoid neutral nouns such as `status` or `state` for booleans, because they do not say
  which value means true. **Optimization.**
- **Test name is the failure message.** The first thing a CI reader sees is the test name, so it must
  be understandable without the code. See `naming.md`.

---

## 9. Comments and headers

Text rots when it repeats something the code, tags or titles already own.

- **Header lists of IDs that no gate reads.** A file header carrying a traceability code list or a run
  of test IDs is **Architectural**. No gate reads those codes, and the per-test tag is the trace handle.
  The header should state the surface, the guarantee, and the prerequisites, with at most one ticket
  reference. Grep for them:
  ```bash
  # Substitute <test-dir> with the test folder you discovered.
  grep -RnE "Traceability:|Tests:\s*U-|IDs:" <test-dir>
  ```
  Adapt the pattern to the project's codes.
- **A doc block that restates the title** is deleted. A comment earns its place only when it carries
  context the title cannot: a data precondition, a deliberately red test, or why it matters.
  **Optimization**, unless the block is out of sync with the title, then **Architectural**.
- **An inline comment that narrates the next line** (`// Click the first option` above a click) is
  deleted. Keep only WHY comments: rationale, workaround, deliberate omission, ticket reference.
  **Optimization**; a cluster of narration comments in one file is **Architectural**.
- **Comment length.** See `failure-messages-and-skips.md` §3.

---

## 10. Reuse-first and extraction destinations

- **Reuse-first (hard, once the project has shared code).** Before anything is authored in a spec, check it
  against the existing shared code and reuse or extend it. New code goes to its proper home, never inline. An
  inline mock, factory, locator or string that duplicates existing capability is **Architectural** even when
  the test passes. Discovery: the folder READMEs and the existing support, page-object, test-data and i18n modules.
- **Each concern has one home.** Each branch below applies only when its home exists in the project:
  - a route mock. If the project has a mocks module, an inline `page.route` in a spec is a finding. If not,
    flag only a mock duplicated across specs and suggest one shared module.
  - a data factory or seed identifier. If the project has a test-data or domain module, an inline factory or
    seed ID in a spec is a finding. If not, flag only one duplicated across specs.
  - a user-facing string. If the project has translations, a hand-typed copy string is a finding (see the
    UI copy check in SKILL.md). If not, copy reused across specs belongs in one test-data module.
  - an API call with auth headers. If the project has an API fixture or central client, a spec that builds
    its own authenticated request is a finding. If not, flag only auth or request setup repeated across specs.
  - a test-ID or attribute locator. If the project has page objects, a locator inline in a spec is a finding,
    and the remedy is a getter on the page object. If not, flag only a locator repeated across specs.
  - a hardcoded locale. If the project has a locale fixture or path helper, a hardcoded locale in a spec is a
    finding. If not, skip this branch.
  Severity: **Architectural**, or **Critical** when the inline copy hides a tautology or a locale-bound assertion.
- A confirmed app bug becomes a ticket, never a loosened assertion or a skip.
