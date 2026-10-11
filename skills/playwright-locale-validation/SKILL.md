---
name: playwright-locale-validation
description: "Keep Playwright API and UI tests locale-agnostic. Use when writing or reviewing locale-prefixed paths, URLs, fixtures, and assertions."
---

# Playwright Locale Validation — Locale-Agnostic Test Rules

> **Scope:** every test under `<e2e-dir>/` (API and UI both — every locale-prefixed path is a candidate).
> **Load alongside `playwright-core`, `playwright-api`, `playwright-ui`** when writing or reviewing tests.
> **Source of truth:** `<locales-module>`, `<env-config-file>`, and the `locale` fixtures in `<fixtures-dir>/api-fixtures.ts` and `<fixtures-dir>/ui-fixtures.ts`.

A test that hardcodes a locale segment such as `/en-gb/` passes on the default locale and silently 404s (or worse — wrong page) on every other one. Violations of these rules slip through code review easily because the default locale always works.

## Placeholders

- `<e2e-dir>` — root folder of the end-to-end test suite.
- `<fixtures-dir>` — folder holding the shared Playwright fixture files.
- `<locales-module>` — module that exports the locale list, the `Locale` type, the released-locale helpers and the path helpers (`uiPath`, `apiPath`, `secondaryLocale`).
- `<env-config-file>` — committed JSON file with the default `E2E_LOCALE`, loaded before any `.env` file.
- `<run-e2e-command>` — the project's command that runs the whole suite.
- `<run-smoke-command>` — the command that runs the smoke subset.
- `<run-full-command>` — the command that runs the full regression suite.
- `<run-headed-command>` — the command that runs one spec in a visible browser.

Map each one to the matching file, folder or command in your project before using this skill.

---

## Why this matters

Every app URL is locale-prefixed:

```
http://localhost/en-gb/
http://localhost/nl-nl/example-items?filter=value
http://localhost/fr-fr/settings
```

Every API endpoint is locale-prefixed:

```
GET /api/en-gb/categories
POST /api/nl-nl/auth/login
GET /api/fr-fr/<resource>/example-item
```

A test with a hardcoded locale segment is locale-bound. It cannot be repurposed for a different locale rollout, a smoke check on another locale, or a regression run against a different deployment without editing the file. That defeats the whole point of having a locale fixture.

---

## The supported locales — `LOCALES` vs `RELEASED_LOCALES`

`<locales-module>` is the source of truth; **don't hardcode a locale list from prose** (the list changes as locales are added — the file wins).

It exports two distinct sets:

```ts
export const LOCALES = [/* the canonical universe */] as const;
export type Locale = (typeof LOCALES)[number];

// The subset actually LIVE. Defaults to a short list defined in the file;
// override with a comma-separated E2E_RELEASED_LOCALES env var (validated against LOCALES).
export const RELEASED_LOCALES: readonly Locale[];
export function isReleasedLocale(locale: string): locale is Locale;
```

**Rule: specs that loop over locales to *run* them iterate `RELEASED_LOCALES`, never `LOCALES`.** `LOCALES` is for the type, `E2E_LOCALE` validation, and coverage data; running unreleased locales fails the suite (e.g. a locale whose backend is not yet provisioned may return errors). Guard single-locale conditionals with `isReleasedLocale(locale)`.

---

## How the default locale is chosen

Two-tier config:

1. **`<env-config-file>`** — canonical default for `E2E_LOCALE`. Loaded by the Playwright config before `.env`.
2. **`<e2e-dir>/.env`** — secrets only. May optionally override `E2E_LOCALE` for local development; that override wins.
3. **Shell `E2E_LOCALE`** — wins over both when set.

The `locale` fixture in `<fixtures-dir>/api-fixtures.ts` (and inherited by `ui-fixtures.ts`) reads `process.env.E2E_LOCALE`, validates it against `LOCALES`, and throws a readable error on a typo. Use the fixture — never read `process.env.E2E_LOCALE` inside a test body.

```ts
// <fixtures-dir>/api-fixtures.ts (real shape)
locale: async ({}, use) => {
  const raw = (process.env.E2E_LOCALE ?? 'en-gb').toLowerCase();
  if (!(LOCALES as readonly string[]).includes(raw)) {
    throw new Error(`E2E_LOCALE="${raw}" is not a supported locale. Supported: ${LOCALES.join(', ')}.`);
  }
  await use(raw as Locale);
},
```

---

## The `uiPath()` and `apiPath()` helpers

`<locales-module>` exposes two helpers. They are the **only** sanctioned way to build a locale-prefixed path.

```ts
export function uiPath(locale: Locale, path: string): string;     // → /<locale>/<path>
export function apiPath(locale: Locale, path: string): string;    // → /api/<locale>/<path>
export function secondaryLocale(primary: Locale): Locale;         // → first locale with a different language prefix
```

```ts
import { uiPath, apiPath } from '<locales-module>';

await page.goto(uiPath(locale, '/'));               // /en-gb/
await page.goto(uiPath(locale, '/example-page'));   // /en-gb/example-page
await page.goto(uiPath(locale, 'example-items'));   // /en-gb/example-items  (leading / optional)
await request.get(apiPath(locale, '/categories'));  // /api/en-gb/categories
```

---

## Running tests against a different locale

Set `E2E_LOCALE` in the environment. No file edits.

```bash
<run-e2e-command>                            # default locale (<env-config-file>)
E2E_LOCALE=fr-fr <run-e2e-command>           # French locale
E2E_LOCALE=nl-nl <run-smoke-command>         # Dutch — smoke only
E2E_LOCALE=de-de <run-full-command>          # German — full regression
```

Or pin the locale per local clone in `<e2e-dir>/.env`:

```dotenv
E2E_LOCALE=nl-nl
```

**Important:** `E2E_LOCALE` is distinct from Playwright's `use.locale`, which controls the **browser's** language/formatting preferences passed to the browser engine. The two are independent — set both if you need browser locale and app locale to match.

---

## Violation patterns to flag

### ❌ Hardcoded locale in `goto()`

```ts
await page.goto('/en-gb/');                    // fails on every other locale
await page.goto('/nl-nl/example-page');        // fails on the default locale
await freshPage.goto(`/en-gb/${slug}`);        // fails on every other locale
```

### ❌ Hardcoded locale in URL assertions

```ts
await expect(page).toHaveURL(/\/en-gb\//);    // fails on nl-nl
await expect(page).toHaveURL('/en-gb/example-page');   // fails everywhere else
```

### ❌ Hardcoded locale in service constructors inside fixtures

```ts
const someService = new SomeService(client, 'en-gb');   // hardcoded
```

### ❌ Reading `process.env.E2E_LOCALE` directly in a test body

```ts
test('…', async ({ page }) => {
  const locale = process.env.E2E_LOCALE ?? 'en-gb';   // bypass the validating fixture
});
```

### ✅ Locale fixture + helpers

```ts
test('main flow', async ({ page, locale }) => {
  await page.goto(uiPath(locale, '/example-page'));
  await expect(page).toHaveURL(new RegExp(`/${locale}/example-page`));
});

resourceFixture: async ({ request, baseURL, locale }, use) => {
  const someService = new SomeService(new ApiClient(request, baseURL as string), locale);
  // …
},
```

---

## Adding `locale` to a new test

1. Import `test`/`expect` from the relevant fixtures file (`<fixtures-dir>/api-fixtures.ts` or `<fixtures-dir>/ui-fixtures.ts`) — never `@playwright/test` directly.
2. Declare `locale` in the parameter list alongside `page`/`request`/etc.
3. Replace every `'/en-gb/...'` string with `uiPath(locale, '...')` (UI) or `apiPath(locale, '...')` (API).
4. Replace every `toHaveURL('/en-gb/...')` with `toHaveURL(new RegExp(\`/${locale}/...\`))`.

```ts
import { test, expect } from '<fixtures-dir>/ui-fixtures';
import { uiPath } from '<locales-module>';

test('page loads', { tag: '@smoke' }, async ({ page, locale }) => {
  await test.step('Navigate to page', async () => {
    await page.goto(uiPath(locale, '/example-items'));
  });
  await test.step(`Assert URL contains the locale segment - Expected: /${locale}/example-items, Actual: ${page.url()}`, async () => {
    await expect(page).toHaveURL(new RegExp(`/${locale}/example-items`));
  });
});
```

---

## Cross-locale comparison tests

When a spec needs to compare two locales (e.g. checking that a translated label differs across locales), use `secondaryLocale(primary)` to pick a locale with a different **language** prefix — it skips same-language variants such as `en-ie` when the primary is `en-gb`.

```ts
import { secondaryLocale } from '<locales-module>';

const primary = locale;
const secondary = secondaryLocale(primary);   // guaranteed different language family
```

---

## Checklist before merging a test

- [ ] No hardcoded locale segment (any entry of `LOCALES`, e.g. `/en-gb/`, `/nl-nl/`) in any `goto()` or `request.*()` call.
- [ ] No hardcoded locale segment in any `toHaveURL()` assertion.
- [ ] Every UI navigation built with `uiPath(locale, path)`.
- [ ] Every API path built with `apiPath(locale, path)` (or via a Service whose constructor took `locale`).
- [ ] `locale` declared as a fixture parameter — not read from `process.env.E2E_LOCALE` inside the test body.
- [ ] Spec runs cleanly under at least one non-default locale: `E2E_LOCALE=fr-fr <run-headed-command> SPEC=specs/...`.
