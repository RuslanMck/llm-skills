---
name: playwright-ui
description: "Browser-specific Playwright rules for UI tests under tests/e2e/specs/ui/. Use for live UI exploration, page objects, interactions, and assertions."
---

# Playwright UI Automation — Browser-Specific Rules

> **Scope:** every UI test under `tests/e2e/specs/ui/`.
> **Load alongside `playwright-core`** — directory layout, env config, tagging, faker, soft assertions, `test.step()`, fixture traceability, locales all live there.
> **Source of truth:** `tests/e2e/playwright.config.ts`, `tests/e2e/fixtures/ui-fixtures.ts`, the page/component classes under `tests/e2e/pages/` and `tests/e2e/components/`. If anything below conflicts, the code wins.

## Placeholders

Map each of these to your own project before using the skill:

- `<app-host>` — public host of the application under test (no scheme).
- `<auth-cookie>` — cookie name that carries the logged-in API token.
- `<auth-state-dir>` — folder where Playwright storage-state files are written (git-ignored).
- `<auth-setup-file>` — the setup project that logs in and writes storage state.
- `<storage-state-builder>` — the helper that turns a login response into a storage-state file.
- `<account-credentials-file>` — the helper that decides which test account a run uses.
- `<test-users-file>` — the registry of test users.
- `<token-fixtures-file>` — fixtures for guest flows using token-based access.
- `<consent-cookie-name>` — cookie that stores the cookie-consent choice.
- `<staging-access-header>` — header a staging environment requires on every request.
- `<backend-dir>` — folder of the API backend (its routes live in `<backend-dir>/routes/api.php`).
- `<pom-lint-script>` — script that enforces Page Object conventions in the fast CI gate.
- `<headed-run-command>` — command that runs the e2e suite in a visible browser.
- `<headed-env-var>` — env var that holds the browser open at the end of a test for demo runs.
- `<project-selector-env>` — env var that registers opt-in Playwright projects.
- `<test-password-env>`, `<prod-user-email-env>`, `<prod-user-password-env>` — env vars holding test-account credentials.
- `<env-config-file>` — environment config file (base URLs, flags).

---

## Coverage discipline — explore the LIVE UI first, test behaviour not presence

**This section is the most important one. Skipping it is how a surface's bugs get missed.**

### 1. Explore the live, hydrated page BEFORE writing or scoping tests

Static inspection — `curl` of SSR HTML + reading source — is **supplementary, never the primary lens**. It cannot reveal:

- **client-rendered content** — dynamic lists, formatted values, data-driven UI, anything populated after hydration (SSR ships empty containers);
- **visual defects** — white-on-white text, broken layout, wrong colours;
- **interaction bugs** — a control that needs two clicks, a filter that doesn't filter, sort that doesn't sort, a toggle that stays visible when it shouldn't.

So for any surface, **first drive it hydrated** like a manual QA pass: Playwright headed (`<headed-run-command>`), or a throwaway `page.goto()` + screenshot / `page.content()` dump *after* hydration. Click every control, change every state, read every value. Record every anomaly — those become findings (ticket + red-by-design guard) and the test list.

### 2. Build an exhaustive functional inventory — coverage is measured against it

List every:
- **interactive control** — buttons, filter controls, sort, pagination, per-page (e.g. "Show 12/24/48"), toggles, inputs, links, "show more / clear all";
- **state** — empty, loading, expanded/collapsed, page 2+, filtered, error, logged-in/out;
- **displayed value** — formatted values, counts, badges, breadcrumbs, headings.

Map each entry to a test. "Coverage" means the inventory is exhausted — **not** a hand-picked subset of the most obvious blocks. If you ship a subset, **state explicitly which controls/states/values are NOT yet covered.** Never imply a surface is done when it isn't.

### 3. Assert the OUTCOME of an action, and the CORRECTNESS of a value — never mere presence

`expect(el).toBeVisible()` / `toBeAttached()` proves an element *renders*, not that it *works*. That is green theatre, and it is forbidden as the substance of a guard. Instead:

- select a filter → assert the list **filters** (count/chip changes); sort → assert order **changes**; paginate → assert the page **changes**; per-page → assert the count **changes**; clear-all → assert one click **clears**; collapse → assert dependent UI **hides**.
- displayed values → assert each value is **well-formed**, **matches** its data source (attributes, API response) where present, and is **consistent** across all blocks where the same value appears. The locale context must match. Presence of an element proves nothing about the correctness of its value.

Encapsulate the interaction + reads in POM methods (see "Strict encapsulation" below); the spec asserts outcomes.

### 4. Validate every guard fails for the right reason before parking it

When a guard targets a known bug, run it **live** first and confirm it goes **red for the actual defect** (the failure message matches reality) — only then convert it to `test.fixme` + ticket link. Never ship a `test.fixme` you have never seen fail correctly; a fixme that is silently broken guards nothing.

---

## Project matrix

`playwright.config.ts` is the source of truth for the matrix — **read it before choosing**; counts and regexes in prose rot. *Setup projects* (e.g. `auth-setup`, `warmup-setup`, and any data-setup project) provide auth state, precondition data, and browser warmup; test projects pull what they need via `dependencies`. The test projects today:

| Project | testMatch | storageState | Purpose |
|---|---|---|---|
| `api` | `specs/api/**/*.spec.ts` | (n/a) | API contract tests via `APIRequestContext` |
| `ui-public` | `specs/ui/<surface>/**` | empty | Guest flows, clean session. `grepInvert: /@mobile/`. Extend the `testMatch` regex for each guest-accessible surface. |
| `ui-<surface>` | `specs/ui/<surface>/**` | `<auth-state-dir>/user.json` | Authenticated surface specs. Add one project per surface that requires auth by default. |
| `ui-admin` | `specs/ui/admin/**` | `<auth-state-dir>/admin.json` | Admin panel (session-cookie auth, NOT the API token; admin routes may not carry a locale prefix). |
| `ui-userjourney` | `specs/ui/user-journey/**` | empty | Full end-to-end flows. 30 s action/nav timeouts. `--disable-blink-features=AutomationControlled` so third-party embedded fields render. |
| `ui-regression` | `specs/regression/**` | empty | Issue-specific regression specs. Auth per-test via `loggedInPage`. |
| `ui-mobile` | `specs/ui/**` (overlap-by-design) | **none** | Pixel 5 emulation. `grep: /@mobile/` is **unconditional** so the project stays opt-in. No storageState; never tag an authenticated spec `@mobile`. |
| `perf` | `specs/perf/**` | empty | **Opt-in — registered only when `<project-selector-env>=perf`.** Lighthouse CWV gates — see `playwright-performance`. |
| `analytics-observe` | `specs/analytics-observe/**` | (n/a, empty) | **Opt-in — registered only when `<project-selector-env>=analytics-observe`.** Assertion-free analytics observation. |

`perf` and `analytics-observe` are **not** part of the default run: the config only spreads each project in when its `<project-selector-env>` selector is set, so `--project=perf` / `--project=analytics-observe` fails unless you export that env var first.

`<auth-state-dir>/user.json` / `<auth-state-dir>/admin.json` are written by the `auth-setup` setup project (`<auth-setup-file>`) before dependent projects start. **`dependencies` is for setup projects only** (e.g. `auth-setup`, `warmup-setup`, and any data-setup project) — never depend on a *test* project like `api`: Playwright `dependencies` runs the entire dependency project's tests, doubling CI time and cascading its failures into yours.

---

## Spec placement (MANDATORY — `testMatch` is location-based)

A UI spec is routed to a project **purely by its path**. It MUST live under one of the surface subfolders the globs above match (check `playwright.config.ts` for the current surface list).

- **A spec at `specs/ui/` root (e.g. `specs/ui/nav-a11y.spec.ts`) is matched by NO functional project.** Only `ui-mobile` (`specs/ui/**` + `grep:/@mobile/`) sees it, and it runs `@mobile` tests only — every desktop/non-mobile test in a root-level spec **never executes in any gate**. This is a silent coverage hole, not a style nit.
- **Pick the folder by the surface under test, not by the concern.** Search-dropdown behaviour (incl. its a11y) → `specs/ui/search/`. Header nav → `specs/ui/navigation/`. a11y/keyboard/focus are `@a11y` tags within that surface's spec.
- **New surface?** Add `specs/ui/<surface>/` AND extend the `ui-public` `testMatch` regex in `playwright.config.ts` in the same change, or the new folder won't run either.
- **Always verify it runs:** `--list` the new spec and confirm it appears under the expected `ui-*` project with count > 0 before handing off.

## The `page` fixture — silent monitors and staging-safe header injection

`fixtures/ui-fixtures.ts` overrides the base `page` fixture. **Read it before writing UI tests** — every UI spec inherits these behaviours.

### What it does

1. **Removes the `navigator.webdriver` marker** via `addInitScript` so third-party bot detection doesn't refuse to render embedded fields.
2. **Strips `extraHTTPHeaders` and re-injects `<staging-access-header>` only on own-origin requests.** The CDP-level `extraHTTPHeaders` from `playwright.config.ts` cannot be filtered by `page.route()` (it's added after routing). Third-party CORS preflights reject any custom header on cross-origin calls. The fixture clears all page-level extra headers, then a scoped route handler attaches `<staging-access-header>` only when the request URL starts with the application's origin. This keeps the staging access check satisfied without breaking third-party calls.
3. **Silently monitors the browser, navigation, and network** (console, redirects, failed/slow requests, 4xx/5xx with bodies, page/context lifecycle) into a buffered `TestLogger` flushed as `debug-log.txt` on every run. Uncaught `pageerror` exceptions are collected separately and **thrown after the test as a hard failure**. The full channel list, log prefixes, and how to extend them live in `playwright-extensive-logging` — that skill is canonical for the logging system.
4. **Pauses on `<headed-env-var>=1`** via `page.pause()` so demo runs hold the browser open at the end of the test.

**Implication:** spec files should not need to install any of these listeners themselves. If a test legitimately produces a 4xx/5xx that should not fail it (e.g. a deliberate negative-path 503 simulation), use `page.route()` to fulfil the response inside the test — the response handler still records it but you can decide whether to assert on it.

---

## Locators — `data-testid` first, always

This application is multi-locale. Visible text is rendered by `t(locale, key)` and changes per locale. **Text-based locators are forbidden.**

| Allowed | When |
|---|---|
| `getByTestId()` | Default for every interactive element. |
| `getByRole()` (no `name`) | Narrowing inside a testid scope, e.g. `getByTestId('login-form').getByRole('button')` |
| Other CSS / attribute selector | Last-resort for third-party widgets without testid hooks. |

| Forbidden | Reason |
|---|---|
| `getByText` | Translated copy — fails on every non-default locale |
| `getByLabel` | Label text is translated |
| `getByPlaceholder` | Placeholder text is translated |
| `getByRole({ name })` | Role name comes from visible text or `aria-label`, both translated |

For component-side `data-testid` rules and naming convention, see `playwright-locators`.

### When a `data-testid` is missing — stop and notify

```
⚠️ Missing data-testid: <element> in <Component>.astro has no data-testid.
   The test cannot be written in a locale-agnostic way until one is added.
   Run an audit per `playwright-locators` and add the attribute before continuing.
```

Do not work around with text/CSS/XPath fallbacks.

### Strict encapsulation — zero DOM queries in spec files

Spec files orchestrate user journeys and assert business outcomes. They MUST NOT contain locators or DOM extraction.

```ts
// ❌ in item.spec.ts — leaks DOM and formatting
const raw = await itemPage.lineItems.first().getByTestId('item-value').textContent();
const value = normaliseDisplayedValue(raw ?? '');

// ✅ encapsulated in ItemPage.ts
async getFirstItemValue(): Promise<string> {
  return readLocatorDisplayedValue(
    this.lineItems.first().getByTestId('item-value'),
    'first item value',
    { source: 'ItemPage' },
  );
}

// ✅ in item.spec.ts
const value = await itemPage.getFirstItemValue();
```

Forbidden in `*.spec.ts`:
- `page.getBy*()`, `page.locator()`
- Chaining locators from POM properties (`itemPage.lineItems.first().getByTestId(...)`)
- Inline `textContent()` + transformation (call a POM method that returns the parsed value)

If the test needs a value the POM doesn't expose, **add a typed getter on the POM**.

---

## AAA pattern — no blind action sequences

Arrange → Act → Assert. After every state-changing action, assert the resulting state before the next action. Don't chain five clicks and assert at the end.

Use **web-first auto-polling assertions** — never read state into a variable and pass it to a non-polling assertion.

```ts
// ✅
await expect(page.getByTestId('success-toast')).toBeVisible();

// ❌ does not auto-poll, races on hydration
const visible = await page.getByTestId('success-toast').isVisible();
expect(visible).toBe(true);
```

Assert business value, not just visibility:

```ts
// ✅
await expect(itemPage.getItemCount()).resolves.toBe(3);

// ❌ visibility doesn't prove the value is correct
await expect(itemPage.itemCountElement).toBeVisible();
```

When a step is purely an assertion, prefix the title with `Assert: `.

---

## Auto-waiting — `playwright-deterministic-awaiting` is the source of truth

```
Read .claude/skills/playwright-deterministic-awaiting/SKILL.md before writing
any wait, locator interaction, or hydration-sensitive code.
```

Quick reminders:

1. `page.waitForResponse` — **register the promise BEFORE the action**. Network-gated waits are the highest-priority strategy.
2. `[data-state="ready"]` waits for vanilla TS components (e.g. a configurator or a file upload).
3. `expect(locator).toBeEnabled()` — pre-click only, when the button is in a known disabled/loading state.
4. `expect.toPass()` — third-party iframes only.
5. `page.waitForTimeout()` — **forbidden everywhere**, no exceptions.

---

## Authentication — API login + `storageState`

> **Staging bypass:** if you build a fixture that creates its own context, you must inject `<staging-access-header>`. The page-fixture handles this for `page` already.

### Hierarchy
1. **API login → `storageState`** (preferred). The `auth-setup` setup project (`<auth-setup-file>`) calls `POST /api/{locale}/auth/login` for the account chosen by `resolveAccountCredentials()` (`<account-credentials-file>`): a **target-aware** selection — a dedicated production test account (`<prod-user-email-env>` / `<prod-user-password-env>`) when the run targets production, otherwise `registeredUser` from `<test-users-file>` (password from `<test-password-env>`). It reads the API token and writes `<auth-state-dir>/user.json` via `<storage-state-builder>` (plus `<auth-state-dir>/admin.json` for the admin panel). It runs only for projects that declare `dependencies: ['auth-setup']`. The token lands in both a cookie (`<auth-cookie>`) and `localStorage` so server-side middleware and the client-side auth store can each read it.
2. **Per-test API login → cookie injection** via the `loggedInPage` fixture (used by the `ui-regression` and any UI-public spec that needs auth). The fixture reads `testUser.passwordEnvVar`, calls `authService.login`, retries on 429, and inserts the token cookie into the page context.
3. **UI login through the form — forbidden** for setup. Filling the login form is for tests that *exercise* the login flow, never for tests that need to *be* logged in.

**Missing-credentials policy:** if the resolved account's password env var (`<test-password-env>`, or `<prod-user-password-env>` for a prod target) is unset, `<auth-setup-file>` writes an empty storageState (non-fatal) and warns. The `@smoke` API suite doesn't need auth, so the suite still boots; authenticated UI specs fail with a clear message at the point of use.

### Reference
- Setup project: `<auth-setup-file>`; storage-state writer: `<storage-state-builder>`
- Per-test login: `loggedInPage` fixture in `tests/e2e/fixtures/ui-fixtures.ts`
- Account dashboard test (uses `storageState`): `tests/e2e/specs/ui/account/account-dashboard.spec.ts`

---

## Test preconditions — API-driven, never UI-driven

If a UI test needs an authenticated session or any other pre-existing state (a record, a saved preference, a linked resource), that state is created via the API service layer — not by clicking through the UI.

```
API fixture exists for this state?
  YES → use it directly
  NO  → endpoint exists in <backend-dir>/routes/api.php?
          YES → add a Service + Zod schema (see playwright-api), then a fixture
                ⚠ ask whether to also add an API spec for the new endpoint
          NO  → blocker — flag to a developer
```

**Fixture bodies are bound by the same rule.** A fixture that drives the registration form to create a user is forbidden, even when consumed by a UI test that exercises the registration flow. The two concerns are separate:

- Test exercises the form → use `registrationPage` POM (no state creation)
- Test needs a pre-existing registered user → use `registeredUser` API fixture

```ts
// ❌ fixture drives the browser to create state
uiRegisteredUser: async ({ page }, use) => {
  const reg = new RegistrationPage(page);
  await reg.goto(locale);
  await reg.fillEmail(email);
  await reg.submit();
}

// ✅ fixture creates state via API, hands the browser to the test
apiRegisteredUser: async ({ authService }, use) => {
  const { body } = await authService.register({ email, password, firstName, lastName });
  try { await use({ email, password, userId: body.data.id }); }
  finally { await authService.deleteUser(body.data.id); }
}
```

---

## Real fixtures available to UI tests

`fixtures/ui-fixtures.ts` extends `api-fixtures.ts`. Everything from API fixtures is available (locale, services, `registeredUser`, and cleanup helpers). **The authoritative inventory is the `UiFixtures` type in `fixtures/ui-fixtures.ts`** — read it before writing a test; every POM/component under `pages/` and `components/` is already wired up there (plus `<token-fixtures-file>` for guest flows using token-based access). Don't trust an enumerated list in prose.

The non-obvious fixtures worth knowing by name:

| Fixture | What it gives you |
|---|---|
| `page` | Wrapped page (silent monitors, staging access header scoping, navigator.webdriver removal). See "The page fixture" above. |
| `freshPage` | `page` + `localStorage.clear()` via `addInitScript`. Use when the test must see the cookie consent banner from a clean state. |
| `consentGivenPage` | `page` with `<consent-cookie-name>` pre-seeded. Configurable via `test.use({ consentType, consentOptions })`. Don't combine with `freshPage`. |
| `pageWithPreloadedState` | **Example** of a pre-seeded-state fixture — `page` whose cookie jar holds the identifier for an API-created resource. Check `UiFixtures` in `fixtures/ui-fixtures.ts` for the current canonical name. (Deprecated fixtures throw on setup — do not use them.) |
| `loggedInPage` | `page` whose cookie jar has `<auth-cookie>` for the user picked by the `testUser` option. Retries 429 with backoff. |
| `authCredentials` | `{ email, password }` for `loggedInUser` — for UI specs that exercise the login form. Throws if the password env var is unset. |

**Always declare what you need in the test parameter list.** Never `new SomePage(page)` inside a test body.

```ts
// ✅
test('view <record>', { tag: '@happy-path' }, async ({ recordPage, header, locale }) => {
  await recordPage.gotoDefault(locale);
  // …
});

// ❌
test('view <record>', async ({ page, locale }) => {
  const record = new RecordPage(page);   // forbidden — instantiate in the fixture
});
```

---

## Page Objects vs Component Objects

| Folder | Use for |
|---|---|
| `tests/e2e/pages/` | A dedicated route. One URL = one Page Object. |
| `tests/e2e/components/` | A widget that appears across multiple routes — header, footer, navigation, cookie consent. |

> **Canonical POM structure = the README in `tests/e2e/pages/`.** That file is the single source of truth for how a Page Object is built (locators as lazy getters, `constructor(private readonly page: Page)`, `goto()` waits internally, guard-only `expect()`, responsibility-band layout, role-suffix names). Read it before writing or refactoring a POM. `<pom-lint-script>` (in the fast CI gate) enforces the mechanically-checkable rules; `playwright-test-review` is the review lens.

**Page Objects** are functional classes — no inheritance, no `BaseTest`, no `BasePage`. `constructor(private readonly page: Page)` (plus `isMobile`/`opts` only when the object genuinely varies). Locators are **lazy getters**, not constructor-assigned fields. They expose locators and multi-step interactions; assertions belong in tests, not POMs (`expect()` in a POM is a readiness/interactability guard only — see the README and `playwright-test-review`).

**Component Objects** never own navigation — no `goto()` on a component. Naming: `Header`, `Footer`, `Navigation` — no `Page` or `Component` suffix. Fixture name = camelCase class name.

```ts
// ✅
export class Header {
  constructor(private readonly page: Page, private readonly isMobile: boolean = false) {
    this.menuButton = page.getByTestId('header-menu-button').locator(':visible');
  }
}

// ❌ component owns navigation
export class Header {
  async goto(locale: Locale) { await this.page.goto(uiPath(locale, '/')); }
}
```

Tests must never depend on each other or use `test.describe.serial()` as a setup substitute. State sharing belongs in fixtures.

---

## Network interception — `page.route()`

Precision tool. Mandatory in two cases, forbidden in the rest.

| Scenario | Required? |
|---|---|
| Simulating infrastructure failures (5xx, timeouts, network errors) on any origin | Mandatory |
| Intercepting third-party calls (any external service the project uses) | Mandatory |
| Mocking internal API for a happy-path test | Forbidden |
| Avoiding API setup with mocks instead of fixtures | Forbidden |

```ts
// ✅ simulate a third-party 500 to test failure UX
await page.route('**/<third-party-host>/**', (route) =>
  route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"Internal Server Error"}' }),
);

// ❌ mock the API endpoint to skip auth setup
await page.route('**/api/<locale>/auth/me', (route) =>
  route.fulfill({ status: 200, body: JSON.stringify({ data: { email: 'fake@example.com' } }) }),
);
```

Always `page.unroute()` after a scoped interception block when the intercepted route should not bleed into later steps.

---

## A/B testing and feature flags

> If the project uses third-party tools of this kind, update this skill to handle them. If it does not, skip this instruction.

---

## Multi-tenant + relative paths

Never hardcode a domain or a locale-prefixed path:

```ts
// ✅
await page.goto(uiPath(locale, '/<page-path>'));

// ❌
await page.goto('https://<app-host>/<locale>/<page-path>');
await page.goto('/<locale>/<page-path>');   // see playwright-locale-validation
```

For visual regression on critical components, `expect(locator).toHaveScreenshot()` is allowed.

---

## Accessibility — `@axe-core/playwright` for `@smoke`

Every `@smoke` UI test runs an axe scan after primary navigation completes.

```ts
import AxeBuilder from '@axe-core/playwright';

test('page is accessible', { tag: '@smoke' }, async ({ page, locale }) => {
  await page.goto(uiPath(locale, '/<page-path>'));
  await expect(page.getByTestId('<page-title-testid>')).toBeVisible();

  const results = await new AxeBuilder({ page })
    .disableRules(['region', 'page-has-heading-one', 'landmark-unique', 'image-redundant-alt'])  // site-wide AppShell issues
    .analyze();
  expect(results.violations).toEqual([]);
});
```

The disabled rules are AppShell/footer structural issues outside any single page's scope. Don't disable rules without a written reason in the test.

---

## Locale validation — mandatory final pass

After writing or modifying any UI test:

> Read `.claude/skills/playwright-locale-validation/SKILL.md` and apply its checklist line by line.

Hardcoded locale-prefix segments (e.g. `/<locale>/`) pass on the default locale and silently 404 on every other one. The locale skill's checklist is the exit gate.

---

## Checklist before merging a UI test

- [ ] Spec file is under `tests/e2e/specs/ui/` (or `specs/regression/`).
- [ ] Imports `test`/`expect` from `'../../../fixtures/ui-fixtures'` — never from `@playwright/test`.
- [ ] No hardcoded URLs or credentials — values come from `<env-config-file>`/`.env` via fixtures.
- [ ] No `page.waitForTimeout()`. All waits follow `playwright-deterministic-awaiting`.
- [ ] `waitForResponse` registered before the action that triggers the request.
- [ ] No XPath, no positional CSS (`:nth-child`).
- [ ] No `getByText`/`getByLabel`/`getByPlaceholder`/`getByRole({ name })`.
- [ ] Every logical block in `await test.step()`. Value/state titles include both Expected and Actual.
- [ ] **Explored the live hydrated page first** (not just curl/source); every interactive control, state, and displayed value inventoried.
- [ ] **Guards assert behaviour/value correctness, not mere presence** (`toBeVisible`/`toBeAttached` is never the substance of a guard).
- [ ] **Coverage stated honestly** — surface's inventory exhausted, or the un-covered controls/states/values are named explicitly.
- [ ] Any `test.fixme` was first seen to **fail for the right reason** before being parked.
- [ ] All API preconditions go through `tests/e2e/services/` via fixture — no UI navigation for setup.
- [ ] No fixture creates state by driving the browser.
- [ ] Page/Component Objects instantiated in fixtures, not in test bodies.
- [ ] Tests are independent — no `test.describe.serial()` as a setup substitute.
- [ ] At least one tier tag (`@smoke`/`@happy-path`/`@regression`); array syntax for multiple.
- [ ] Every `@smoke`/`@happy-path` UI test has at least one `@regression` counterpart.
- [ ] `page.route()` only used for infrastructure failures or third-party interception.
- [ ] `@smoke` UI tests include an axe-core scan after primary navigation.
- [ ] Every locale-sensitive or origin-dependent flow uses relative paths via `uiPath(locale, ...)`.
- [ ] Locale-validation checklist applied (no hardcoded locale prefix).
