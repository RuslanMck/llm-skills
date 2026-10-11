---
name: playwright-zod-strict-schema-envelope
description: "Backend adds a field to an API response and the e2e @smoke gate fails with ZodError unrecognized_keys — strict Zod schemas must mirror every new field. Covers the mirror rule, required-vs-optional choice, strict-vs-open decision, and the auth-setup blast radius."
version: 2.0.0
---

# Zod `.strict()` rejects new response fields — mirror them

## Placeholders

- `<contracts-dir>` — the shared package at the repo root that holds the Zod schemas for API responses.
- `<backend-dir>` — the backend application directory that contains the response Resources.
- `<frontend-dir>` — the frontend application directory.
- `<base-branch>` — the branch that backend PRs are compared against.
- `<auth-schema>` — the schema that validates the login/session response (e.g. `AuthUserSchema`).
- `<auth-resource>` — the backend Resource class that serializes the auth/session response.
- `<nested-schema>` / `<nested-field>` — a strict sub-schema composed inside `<auth-schema>` and its corresponding field name.
- `<upstream-field>` — an example field name passed verbatim from an external API.

## Symptom

A backend PR adds a field to a JSON response (any nesting level — envelope, nested sub-object, top-level resource). Laravel tests + PHPStan pass, but the Playwright @smoke gate fails deterministically (all retries) with:

```
ZodError: [{ "code": "unrecognized_keys", "keys": ["<newField>"], ... }]
```

Strict schemas reject unknown keys by design — that's the consumer contract doing its job. **Never switch the schema to `.passthrough()` to silence it. Mirror the field instead.**

## Where the schema lives — check BOTH locations

- **`<contracts-dir>/schemas/*.zod.ts`** (repo root) — shared contracts package; auth and other core domains live here and are re-exported via `tests/e2e/schemas/*`. This is usually the file to patch.
- **`tests/e2e/schemas/*.schema.ts`** — test-local schemas.

```bash
grep -rn "\.strict()" <contracts-dir>/schemas/ tests/e2e/schemas/
```

**Worktree trap:** `<contracts-dir>/` is at the repo root (not under `<frontend-dir>/` or `<backend-dir>/`). Stage it from inside the worktree and verify it landed: `git show HEAD -- <contracts-dir>/schemas/<file> | head -3` — empty output means it wasn't committed.

## Fix — mirror the field, choose required vs optional deliberately

```ts
// conditional field (only present in some 200s, e.g. only during impersonation):
impersonatedBy: z.string().nullish(),

// contract guarantee (every 200 MUST carry it) — REQUIRED, so a regression
// that drops the field fails CI:
_meta: ResourceMetaSchema,
```

Rule of thumb: if the backend DTO throws when the field is missing on a 200, the Zod schema requires it too. `.optional()` on a guaranteed field lets a future refactor silently drop it.

For a **nested** object, add a sub-schema mirroring the PHP DTO and wire it in (`details: ItemDetailsSchema.nullable()`); the shape must mirror the PHP return array key-for-key.

## When `.strict()` itself is wrong — verbatim passthrough data

`.strict()` is only appropriate when **our own code controls every key** (the BFF output shape). Sub-schemas that receive verbatim upstream data (external APIs, external SaaS — e.g. a resource that passes an upstream field through as `$payload['<upstream-field>'] ?? null`) must stay **open**, or any additive upstream API change becomes a runtime parse failure. When fixing one, update the JSDoc to say "Not strict — the upstream API may add fields" and add a forward-compat test that parses an object containing an extra key.

Detection: `grep -n "\.strict()" <contracts-dir>/schemas/<domain>.zod.ts`, then check whether the Laravel Resource remaps the field or passes it verbatim.

## Blast radius — auth schemas break EVERYTHING

`<auth-schema>` (`<contracts-dir>/schemas/auth.zod.ts`) validates the login response inside the `auth-setup` project. A missing field there fails setup **before any test runs**, writes an empty storageState, and cascades every authenticated test to FAIL/SKIP, so one unmirrored field can fail the whole run. Any change to `<auth-resource>::toArray()` must mirror into `<auth-schema>` in the same PR.

**Mind the nested schemas too.** `<auth-schema>` composes other strict schemas — notably `<nested-field>: z.array(<nested-schema>)`, and `<nested-schema>` is itself `.strict()`. So a backend change to the nested payload breaks `auth-setup` even though `<auth-schema>`'s own top-level keys are untouched. Mirror the change into the specific nested schema, not only `<auth-schema>`.

## Prevention — audit before opening a backend PR that touches Resources

```bash
# fields added to any Resource in the diff
git diff origin/<base-branch> -- <backend-dir>/app/Http/Resources/ \
  | grep -E "^\+\s+'[a-zA-Z_]+'\s*=>" | grep -oE "'[a-zA-Z_]+'" | sort -u

# strict schemas that could reject them
grep -rn "\.strict()" <contracts-dir>/schemas/ tests/e2e/schemas/
```

Every new field from the first command must appear in the matching schema — including deeply nested ones (nested objects, array items, root-level fields).

## Related skills

- `playwright-api` — Zod conventions for new schemas (strict envelope, `.passthrough()` inner objects for upstream data, v4 idioms)
