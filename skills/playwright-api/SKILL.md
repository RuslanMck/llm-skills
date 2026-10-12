---
name: playwright-api
description: "HTTP-specific Playwright rules for contract and integration tests under <e2e-dir>/specs/api, including services, schemas, and API fixtures."
---

# Playwright API Automation — HTTP-Specific Rules

> **Scope:** every contract / integration test under `<e2e-dir>/specs/api/`.
> **Load alongside `playwright-core`** — directory layout, env config, tagging, faker, soft assertions, `test.step()`, fixture traceability, locales all live there.
> **Source of truth:** `<e2e-dir>/services/`, `<e2e-dir>/schemas/`, `<e2e-dir>/fixtures/api-fixtures.ts`. If anything below conflicts, the code wins.

## Placeholders

Map these to your own project before using this skill:

- `<e2e-dir>` — root of the end-to-end test suite (holds `specs/`, `services/`, `schemas/` and `fixtures/`).
- `<contracts-dir>` — shared schema package at the repository root, if your project has one.
- `<backend-platform>` — the external platform the application's backend-for-frontend (BFF) reads its data from.
- `<ticket-prefix>` — the issue-tracker key prefix used in debt markers.
- `<services-lint-script>` — the repo's lint check for Service classes.
- `<staging-secret-env>` and `<bypass-header>` — the environment variable holding the staging-gate secret, and the HTTP header that carries it.
- `<internal-secret-env>` and `<internal-secret-header>` — the same pair, for internal-only endpoints.

---

## Canonical example

`<e2e-dir>/specs/api/health/health.spec.ts` is the reference. `<e2e-dir>/services/HealthService.ts` and `<e2e-dir>/services/AuthService.ts` are the reference Service classes. Read them before writing a new spec.

```ts
// specs/api/health/health.spec.ts (excerpt)
import { test, expect } from '../../../fixtures/api-fixtures';

test.describe('GET /api/health', { tag: ['@api', '@smoke'] }, () => {
  test('A-H1: returns 200 with a valid health payload', async ({ healthService }) => {
    const { response, body } = await healthService.getHealth();

    await test.step(`Verify Status Code - Expected: 200, Actual: ${response.status()}`, async () => {
      expect(response.status()).toBe(200);
    });

    await test.step('Verify Health Payload Status', async () => {
      expect(body, 'Health body should parse against schema on 200').not.toBeNull();
      expect(body!.status).toBe('healthy');
    });
  });
});
```

### Negative-path URLs MUST be truly unrouted

A path that just uses an invalid locale (`/api/xx-xx/health`) depends on `resolve.locale` middleware behaviour and may return 400, 422, or a redirect. Use a path that bypasses every middleware:

```ts
// HealthService.ts
private readonly UNKNOWN_ENDPOINT = '/api/__playwright_unknown_route__';

// ❌ depends on locale middleware rejecting unknown locales
private readonly INVALID_ENDPOINT = '/api/xx-xx/health';
```

---

## `ApiClient` — the only HTTP abstraction

> **Staging bypass:** any `request.newContext()` you create yourself (helpers, manual fixtures) must inject `extraHTTPHeaders: { '<bypass-header>': process.env.<staging-secret-env> }`. The config's `use.extraHTTPHeaders` only reaches test-worker contexts. See `playwright-core` → "Staging bypass header".

All HTTP calls go through `<e2e-dir>/services/ApiClient.ts`. Never call `request.get()` / `request.post()` directly in a spec or service.

`ApiClient` records every request as a `test.step()` so the URL and timing show up in the HTML report. It also handles the rare case where the call runs **outside a test context** (e.g. inside `globalSetup`) — the `withOptionalTestStep` helper falls back to a plain request when `test.step()` is unavailable, so the same Service class works in both contexts.

```ts
// <e2e-dir>/services/ApiClient.ts (current shape)
export class ApiClient {
  constructor(private request: APIRequestContext, private baseURL: string) {}

  private async withOptionalTestStep(label: string, run: () => Promise<APIResponse>) {
    try { return await test.step(label, run); }
    catch (error) {
      if ((error as Error).message.includes('test.step() can only be called from a test')) return run();
      throw error;
    }
  }

  async get(endpoint: string, options?: ...): Promise<APIResponse> { /* withOptionalTestStep */ }
  async post(endpoint: string, options?: ...): Promise<APIResponse> { /* withOptionalTestStep */ }
  // PUT, PATCH, DELETE all follow the same pattern
}
```

Spec files never construct `ApiClient`. Services own it; tests receive Service instances via fixtures.

```ts
// ✅
test('A-H1', async ({ healthService }) => {
  const { response } = await healthService.getHealth();
});

// ❌ bare request call
test('<resource>', async ({ request }) => {
  const response = await request.get('/api/<locale>/<resource>');
});

// ❌ ApiClient inside a spec
test('<resource>', async ({ request, baseURL }) => {
  const api = new ApiClient(request, baseURL as string);
});
```

External HTTP libraries (`axios`, `node-fetch`, `got`) are forbidden in test or service code.

---

## Service Object Pattern — locale-aware

Every endpoint family lives in a Service class under `<e2e-dir>/services/`. Reference: `AuthService.ts`, `HealthService.ts`, plus any existing services already wired up in `api-fixtures.ts`.

### Responsibilities

- Build endpoint URLs using `locale` (constructor arg, defaults to `'en-gb'`)
- Inject auth headers from `process.env` or method args
- Call through `ApiClient` so every request appears in the report
- Parse response bodies with the shared `parseResponse` helper from `services/parseResponse.ts`
- Return `ParsedResult<T> = { response, body, error }`
- Never assert — assertions are the test's job

### `parseResponse` is the canonical body parser

`<e2e-dir>/services/parseResponse.ts` exports three helpers:

| Helper | Use |
|---|---|
| `parseJsonOrText(response)` | Reads body as text; tries JSON. Non-JSON (e.g. nginx 502 HTML) returns a synthetic error object instead of throwing `SyntaxError`. |
| `parseResponse(response, schema, isSuccess?)` | Default for typed endpoints. Validates with `schema` on success, with `ApiErrorSchema` on failure. `isSuccess` defaults to `r.ok()`; pass `(r) => r.status() === 201` for endpoints whose success status is not 200. |
| `parseResponseLoose(response, isSuccess?)` | Debt marker, not an exemption. Same shape as `parseResponse` but no body schema. Only for endpoints that do not yet have a schema in `<contracts-dir>`, and the call **must** carry a same-line `TODO(<ticket-prefix>-NNNN)`. `<services-lint-script>` rule 5a flags unmarked calls. Switch to `parseResponse` once the schema exists. |

```ts
// services/AuthService.ts (real shape)
export class AuthService {
  private readonly api: ApiClient;
  private readonly throttleRetryDelaysMs = [800, 1500, 2500];

  constructor(request: APIRequestContext, baseURL: string, private readonly locale: string = 'en-gb') {
    this.api = new ApiClient(request, baseURL);
  }

  async register(payload: RegisterPayload): Promise<ParsedResult<RegisterResponse>> {
    const response = await this.api.post(`/api/${this.locale}/auth/register`, {
      data: payload,
      headers: { 'Content-Type': 'application/json' },
    });
    return parseResponse(response, RegisterResponseSchema, (r) => r.status() === 201);
  }

  async login(email: string, password: string): Promise<ParsedResult<LoginResponse>> {
    const response = await this.api.post(`/api/${this.locale}/auth/login`, {
      data: { email, password },
      headers: { 'Content-Type': 'application/json' },
    });
    return parseResponse(response, LoginResponseSchema);
  }

  // Privacy-preserving teardown — see "User cleanup is redaction, not deletion" below.
  async redactUser(userId: string | null | undefined): Promise<void> { /* … */ }
}
```

### 429 handling lives in `ApiClient` — never add per-service backoff

`ApiClient`'s default verb methods (`get`/`post`/`put`/`patch`/`delete`) auto-retry on `429 Too Many Requests` (up to 3 attempts, honouring `Retry-After` / rate-limit-reset headers, jittered fallback delays — read the policy doc-comment at the top of `services/ApiClient.ts`). The escape-hatch `getRaw` / `postRaw` methods deliberately do **not** retry — use them only when you need the untouched response. **Do not** add retry, backoff, or `sleep` logic in a Service class or fixture — competing retry policies stack multiplicatively and a long 429 chain can already exceed the 30 s per-test timeout. The legacy per-service helpers still present as tracked debt (`AuthService.postWith429Backoff`, `ItemService.getWith429Backoff`; `playwright-test-review` flags them) — always go through the `ApiClient` verb methods instead, and don't copy these into new services.

### Token injection

Bearer tokens come from `authService.login(...)` and are passed as method args:

```ts
async profile(token: string): Promise<ParsedResult<ProfileResponse>> {
  const response = await this.api.get(`/api/${this.locale}/auth/profile`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return parseResponse(response, ProfileResponseSchema);
}
```

Internal-secret-protected endpoints (admin, webhook helpers) read from `process.env.<internal-secret-env>`:

```ts
private headers = {
  '<internal-secret-header>': process.env.<internal-secret-env>!,
  'Content-Type': 'application/json',
};
```

### Encapsulation rule

Spec files MUST NOT contain hardcoded endpoint strings. They MUST NOT instantiate `ApiClient`. All URL construction, header injection, and Zod parsing happens inside the Service class. Spec files only call the method.

### API fixtures

Service instances are injected via `<e2e-dir>/fixtures/api-fixtures.ts`. Read it — every existing service is already wired up with the active `locale`.

```ts
// fixtures/api-fixtures.ts (excerpt)
authService: async ({ request, baseURL, locale }, use) => {
  await use(new AuthService(request, baseURL as string, locale));
},
healthService: async ({ request, baseURL }, use) => {
  await use(new HealthService(request, baseURL as string));   // health is locale-agnostic
},
```

When you add a new service, register a fixture in `api-fixtures.ts`. Tests then declare it in the parameter list.

---

## Zod — mandatory contract validation

Every typed endpoint response is parsed with a Zod schema before assertion. Raw `await response.json()` followed by `expect(json.foo)` is forbidden.

### Schemas live in TWO places — check both

- **`<contracts-dir>/schemas/*.zod.ts`** (repo root) — the shared contracts package. The load-bearing schemas for auth and other core domains live here and are **re-exported** by `<e2e-dir>/schemas/*` (e.g. `auth.schema.ts`). When a Laravel Resource adds a field, this is usually the file to patch.
- **`<e2e-dir>/schemas/`** — test-local schemas for endpoints not covered by the contracts package.

When a strict schema rejects a new backend field, follow `playwright-zod-strict-schema-envelope` — it covers the mirror rule, required-vs-optional choice, and the auth-setup blast radius.

### Zod v4 idioms

The suite is on Zod **v4**. Use v4 string-format helpers — v3 `.email()` etc. on `z.string()` are deprecated:

| v3 (deprecated) | v4 (required) |
|---|---|
| `z.string().email()` | `z.email()` |
| `z.string().uuid()` | `z.uuid()` |
| `z.string().url()` | `z.url()` |
| `z.string().datetime({ offset: true })` | `z.iso.datetime({ offset: true })` |

### Strict by default

Object schemas describing API responses use `.strict()` so unknown fields fail the contract — that's the whole point of a consumer contract. The two exceptions:

- **`ApiErrorSchema`** stays open: Laravel attaches `trace`, `file`, `exception` only when `APP_DEBUG=true`.
- **Resource schemas backed by `<backend-platform>`** use `.passthrough()` on the inner backend object so new backend fields don't break the test, while the outer envelope (`{ data: … }`) stays `.strict()`.

```ts
// schemas/resource.schema.ts
export const ResourceSchema = z.object({
  id: z.uuid(),
  name: z.string().min(1),
  status: z.string(),
}).strict();

export const ResourceListResponseSchema = z.object({
  data: z.array(ResourceSchema),
  total: z.number().int().nonneg(),
  offset: z.number().int().nonneg(),
  limit: z.number().int().positive(),
}).strict();

// schemas/auth.schema.ts (excerpt) — open-ended on purpose
export const ApiErrorSchema = z.object({
  error: z.string().optional(),
  message: z.string().optional(),
  errors: z.record(z.string(), z.array(z.string())).optional(),
});

// Backend-backed shape — passthrough on inner, strict on envelope
export const BackendRecordSchema = z.object({ /* known fields */ }).passthrough();
export const BackendRecordDetailResponseSchema = z.object({ data: BackendRecordSchema }).strict();
```

---

## Data isolation & teardown

API tests are self-contained. No reliance on pre-seeded DB state, no shared identifiers across tests. Each test that creates a resource cleans it up via a fixture.

`try/finally` in a spec file is a hard violation. Two fixture patterns cover everything.

### Pattern A — encapsulated fixture (e.g. `registeredUser`)

The fixture creates the resource, yields it, deletes/redacts it. The spec contains zero setup or teardown code. Use when the test does **not** need to assert the creation response.

```ts
test('A-L1: login returns 200', { tag: '@smoke' }, async ({ authService, registeredUser }) => {
  const { response } = await authService.login(registeredUser.email, registeredUser.password);
  expect(response.status()).toBe(200);
});
```

### Pattern B — tracker fixture (e.g. `cleanupRecord`)

Use when the test **must** assert the creation response. Create inline, immediately call `cleanupX.track(id)` — **before any assertion that might throw** — and the fixture redacts every tracked ID after the test, including on failure.

```ts
test('A-R1: register returns 201', { tag: '@smoke' }, async ({ authService, cleanupRecord }) => {
  const { response, body, error } = await authService.register(payload);
  cleanupRecord.track(body?.data.record?.id);   // ← before assertions

  await test.step(`Verify Status Code - Expected: 201, Actual: ${response.status()}`, async () => {
    expect(response.status(), `error: ${JSON.stringify(error)}`).toBe(201);
  });
});
```

### User cleanup is redaction, not deletion

`AuthService.redactUser(id)` — not `deleteUser`. It calls a redact endpoint that overwrites PII with anonymised placeholders while keeping the record for legal retention. **Never** add a hard-delete fixture for users. The redact endpoint is best-effort — failures are swallowed so a missing teardown never masks a real assertion.

---

## Verifying backend data via the BFF

The application frontend never talks to `<backend-platform>` directly:

```
Playwright → Laravel BFF (/api/{locale}/...) → BackendClient → backend API
```

Backend verification specs follow the chain end-to-end, never the backend platform's SDK or its API host directly.

### Pattern: login → list → fetch detail

Read endpoints that pull from `<backend-platform>` under `/api/{locale}/auth/*` require a Sanctum Bearer token from `authService.login(...)`. Pass it as a method arg.

```ts
let sharedToken = '';
let sharedItemId = '';

test.describe('<Resource> API — backend verification via BFF', { tag: ['@api'] }, () => {
  test.describe.configure({ mode: 'serial' });

  test('A-RES1: login + fetch <resource> list', { tag: '@smoke' }, async ({ authService, resourceService, registeredUser }) => {
    const { body: loginBody } = await authService.login(registeredUser.email, registeredUser.password);
    sharedToken = loginBody!.data.token;

    const list = await resourceService.listItems(sharedToken);   // fetched live, never hardcoded
    const first = (await list.json()).data.find((o: { id: string | null }) => o.id !== null);
    expect(first).toBeTruthy();
    sharedItemId = first!.id;
  });

  test('A-RES2: verify backend <resource> fields', { tag: '@smoke' }, async ({ resourceService }) => {
    const { response, body } = await resourceService.getById(sharedItemId, sharedToken);
    expect(response.status()).toBe(200);
    // assert backend fields…
  });
});
```

Hardcoding an ID from staging is fragile — staging data resets. Fetch the list at runtime and pick a real record from it.

### Test-environment quirks

| Symptom | Cause | Workaround |
|---|---|---|
| A slow endpoint exceeds the default timeout budget | An unindexed lookup in the test environment | Give that endpoint its own, larger budget; keep the default for everything else |
| A missing resource returns a server error instead of 404 | The backend throws on lookup values it cannot route | Assert `status >= 400`, not exactly 404; comment the environment behaviour |
| An endpoint returns a "disabled" error in the test environment | The feature is switched off there | Skip the test with a reason that names the environment setting
---

## Negative coverage requirements

For every `@smoke` or `@happy-path` API test, ship the matching `@regression` negatives:

| Scenario | Status | Tag |
|---|---|---|
| Missing / invalid auth | 401 | `@regression` (or `['@smoke', '@regression']` for critical-path auth) |
| Insufficient permissions | 403 | `@regression` |
| Resource doesn't exist | 404 | `@regression` |
| Missing required field | 422 | `@regression` |
| Malformed payload (wrong types, extra fields) | 422 or 400 | `@regression` |

Every negative response body is parsed against `ApiErrorSchema`. A `@happy-path` shipped without these negatives fails Definition-of-Done.

---

## Checklist before merging an API test

- [ ] Spec is under `<e2e-dir>/specs/api/`.
- [ ] Imports `test`/`expect` from `'../../../fixtures/api-fixtures'`.
- [ ] No hardcoded endpoint strings in the spec — every URL lives in a Service class.
- [ ] No `ApiClient` instantiation in the spec — only inside Service classes.
- [ ] All HTTP calls flow through `ApiClient` (so they appear as `test.step()` in the report).
- [ ] Every assertion group wrapped in `test.step()`. Status/value step titles include both Expected and Actual.
- [ ] No `axios`, `node-fetch`, `got`, or bare `fetch()` in service or test code.
- [ ] Service uses `parseResponse` from `services/parseResponse.ts` — non-JSON responses do not blow up with `SyntaxError`. `parseResponseLoose` is a debt marker (same-line `TODO(<ticket-prefix>-NNNN)` required; `<services-lint-script>` rule 5a).
- [ ] No service-level 429 retry/backoff/sleep — `ApiClient` owns the 429 policy.
- [ ] Response bodies validated via Zod v4 (`z.email()`, `z.uuid()`, `z.iso.datetime()` — no deprecated `z.string().email()` etc.).
- [ ] Response schemas use `.strict()` — except `ApiErrorSchema` (open) and backend inner objects (`.passthrough()`).
- [ ] Negative-path 404 tests hit a truly unrouted URL (`/api/__playwright_unknown_route__`).
- [ ] Service exists under `<e2e-dir>/services/` and is registered as a fixture in `api-fixtures.ts`.
- [ ] Zod schema exists under `<e2e-dir>/schemas/` for every typed response.
- [ ] No `try/finally` in spec files — teardown lives in fixtures.
- [ ] Pattern A (encapsulated) for tests that don't assert the creation response; Pattern B (tracker) for tests that do — `cleanupX.track(id)` called BEFORE any assertion that can throw.
- [ ] User teardown uses `redactUser` — never `deleteUser` (legal retention).
- [ ] Fixture setup/teardown wrapped in `await test.step('Fixture Setup: …')` / `'Fixture Teardown: …'`.
- [ ] Credentials and URLs come from env vars, never hardcoded.
- [ ] Locale-sensitive endpoints use the `locale` fixture from `api-fixtures.ts`.
- [ ] At least one tier tag (`@smoke`/`@happy-path`/`@regression`); `@api` and other metadata tags optional.
- [ ] Multi-tag uses array syntax — never a comma-separated string.
- [ ] Every `@smoke`/`@happy-path` API test has `@regression` counterparts covering at least 401, 404, and 422.
- [ ] Multiple independent response field checks use `expect.soft()` with descriptive messages.
- [ ] `response.ok()` and status-code assertions are hard `expect()` — never soft.
