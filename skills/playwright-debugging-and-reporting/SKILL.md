---
name: playwright-debugging-and-reporting
description: "Investigate Playwright failures, classify test/code/environment causes, collect evidence, and prepare handoff to ticket creation."
---

# Playwright Debugging and Reporting

> **Scope:** Investigating Playwright test failures (UI and API), classifying root causes, collecting evidence, and handing that evidence to ticket creation. Marking tests appropriately.
> Use when: a test fails and you need to determine whether it is a test problem, a code problem, or an environment problem — and then handle each case correctly.
> Prerequisite skills: `playwright-core`, `playwright-ui`, `playwright-api`, `playwright-extensive-logging`.
> Ticket creation owns ticket structure, scope, priority, labels, and creation. This skill never composes ticket bodies; it produces the evidence that ticket creation consumes.

## Placeholders

- `<ui-project>` — the Playwright project that runs UI journey specs
- `<headed-env-var>` — the environment variable that enables headed browser mode with a slow-motion delay
- `<backend-dir>` — the server-side application folder in the repo
- `<frontend-dir>` — the client-side application folder in the repo
- `<component-dir>` — the folder that holds the main interactive component
- `<locale>` — the locale segment in API routes, if the app has one
- `<journey>` — the folder that groups UI journey specs
- `<domain>` — a feature or domain name used in schema and controller names
- `<spec-name>` — a spec file name without its `.spec.ts` suffix
- `<endpoint>` — the API route being searched for in logs
- `<resource>` — the API resource or entity type in route paths
- `<tier-field>` — the payload field that selects an option or tier
- `<ticket-url>` — the ticket URL returned by ticket creation
- `<price-field>` — a payload or calculated field that holds a computed or selected value
- `<configurator-file>` — the main TypeScript file for the main interactive component
- `<request-validator>` — the request validation class name for an operation
- `<service-class>` — the service class handling the relevant domain logic

---

## Overview

This skill owns **debugging and evidence collection**. It does not own ticket composition. When this skill detects a code-side failure, it packages the findings and hands them off; ticket creation handles structure, scope, priority, labels, and the create call.

The pipeline has five phases:

1. **Run** — execute the spec with full artifact capture
2. **Triage** — read artifacts to classify failure modes
3. **Investigate** — correlate logs with actual source code
4. **Act** — for test-side failures, fix the test; for code-side failures, mark the test with `.fixme()` and prepare an evidence package
5. **Hand off** — pass the evidence package to ticket creation and annotate the `.fixme()` with the returned ticket URL

Each phase differs slightly between UI specs and API specs. Both are described below.

---

## Phase 1 — Run with full artifact capture

### UI specs

```bash
cd tests/e2e && npx playwright test <spec-path> \
  --project=<ui-project> \
  --repeat-each=<repeat-count> \
  --trace=on \
  --workers=<worker-count>
```

**Flags:**
- `--trace=on` — captures trace for every run (pass and fail), not just failures. Required for timeline correlation.
- `--workers=1` for deterministic serial runs; `--workers=3+` to stress-test under concurrency (reveals race conditions and connection pool exhaustion).
- `--video=on` is **not** a valid CLI flag — video is a project-level config. `retain-on-failure` is already set in `playwright.config.ts`.

**Never use `<headed-env-var>=1`** — it enables a slow-motion delay that masks timing bugs.

### API specs

```bash
cd tests/e2e && npx playwright test <spec-path> \
  --project=api \
  --repeat-each=<repeat-count> \
  --workers=<worker-count>
```

API tests run headlessly and do not produce traces, screenshots, or video. Their primary artifact is `api-log.txt`.

**Always run from the repo root via `make` or `cd tests/e2e && npx playwright test ...`** — never `npx playwright --prefix tests/e2e`, which can't find the config.

---

## Phase 2 — Triage failures from artifacts

After the run, all results are under `tests/e2e/test-results/`. This directory is **gitignored** — never reference artifact file paths in the evidence package; embed the content directly.

### Artifact layout by spec type

**UI spec failure** (4 files = failed run):
```
test-results/<ui-project>-<name>-<retry>/
  error-context.md    ← error message + page snapshot YAML + spec source
  trace.zip           ← step-by-step trace with DOM snapshots
  test-failed-1.png   ← screenshot at point of failure
  video.webm          ← full test video
```

**UI spec pass** (1 file = passed run):
```
test-results/<ui-project>-<name>/
  trace.zip
```

**API spec failure** (1–2 files):
```
test-results/api-<name>-<retry>/
  api-log.txt         ← every request/response with timing; full bodies on 4xx/5xx
```

There is no `error-context.md` for API specs. The terminal output carries the assertion error. The `api-log.txt` carries the HTTP evidence.

### Identify pass vs fail

```bash
# UI — 4 files = FAIL, 1 = pass
for dir in tests/e2e/test-results/<prefix>*/; do
  count=$(ls "$dir" 2>/dev/null | wc -l | tr -d ' ')
  echo "$count $(basename $dir)"
done

# API — presence of api-log.txt in a retry directory indicates a failed attempt
ls tests/e2e/test-results/api-*/api-log.txt 2>/dev/null
```

---

## Phase 2a — Extracting evidence from UI artifacts

### Extract the error message

```bash
awk '/^# Error details/,/^# Page snapshot/' \
  "tests/e2e/test-results/<run-dir>/error-context.md"
```

### Extract the page snapshot at failure

```bash
awk '/^# Page snapshot/,/^# Source/' \
  "tests/e2e/test-results/<run-dir>/error-context.md" \
  | grep -i "<keyword>"
```

The snapshot is a YAML-like accessibility tree at the exact moment of failure. It is the most reliable source of truth for:
- Which URL the browser was on
- Which elements were visible / hidden / disabled
- Text content of paragraphs (error messages, labels, status text)
- Button states (`[disabled]`, `[checked]`, `[cursor=pointer]`)

**Key patterns to grep for:**
```bash
# Labels and status text
grep -i "paragraph\|label\|status\|disabled\|\.\.\." error-context.md

# Error messages rendered on the page
grep -i "cURL\|error\|timeout\|not found" error-context.md

# Button and form state
grep -i "button\|textbox\|radio\|checkbox\|label.*hidden\|hidden.*label" error-context.md

# URLs and page transitions
grep -i "/url:\|confirmation" error-context.md
```

### Extract spec source lines around the failure

```bash
grep "^\s*[0-9]" error-context.md | grep "|" | head -30
```

### Extract the `debug-log.txt` network timeline (UI tests only)

Every UI test produces `debug-log.txt` in the same result directory. It contains:
- `[Navigation]` — every main-frame URL change
- `[Browser] console.<type>` — all browser console output
- `[Timeline]` — every own-origin request/response with elapsed ms
- `[Network Error]` — 4xx/5xx responses with full request + response bodies
- `[Slow Request]` — requests exceeding 30 s
- `[Network] Request failed` — requests that failed at network level (ERR_*)

```bash
# All network errors in the debug log
grep "\[Network Error\]\|\[Network\] Request failed\|\[Slow Request\]" \
  "tests/e2e/test-results/<run-dir>/debug-log.txt"

# Full body for a specific failing endpoint
grep -A 20 "POST.*<endpoint>" \
  "tests/e2e/test-results/<run-dir>/debug-log.txt"

# Navigation trail leading to failure
grep "\[Navigation\]" \
  "tests/e2e/test-results/<run-dir>/debug-log.txt"

# Browser console errors only
grep "\[Browser\] console\.error\|\[Browser\] console\.warn" \
  "tests/e2e/test-results/<run-dir>/debug-log.txt"

# All request timings (useful for spotting the slow call before a timeout)
grep "\[Timeline\]" \
  "tests/e2e/test-results/<run-dir>/debug-log.txt"
```

**What `debug-log.txt` does NOT contain:**
- `console.log` output printed by test-runner code (`console.log(...)` in spec files) — those go to terminal stdout only
- Playwright internal trace events — those are in `trace.zip`

---

## Phase 2b — Extracting evidence from API artifacts

API test runs do not produce `error-context.md`. The two sources of evidence are:

1. **Terminal stdout** — the assertion error and step name (may be truncated in CI)
2. **`api-log.txt`** — the full HTTP timeline, attached via the `api-fixtures.ts` logging layer on every run

The `api-log.txt` line format (`[API]` timeline entries, `[API Error]` blocks with request + response bodies on 4xx/5xx responses — the fixture gates on status `>= 400`, so 3xx redirects are not flagged) is documented in `playwright-extensive-logging` — that skill is canonical for what each log layer captures.

### Extract all API errors from a run

```bash
grep -A 10 "\[API Error\]" \
  "tests/e2e/test-results/<run-dir>/api-log.txt"
```

### Extract the full timeline for a specific endpoint

```bash
grep "POST.*<endpoint>\|GET.*<endpoint>" \
  "tests/e2e/test-results/<run-dir>/api-log.txt"
```

### Check for timeout patterns (no `←` line after `→`)

```bash
# Requests that were sent but never received a response line
awk '/→  (GET|POST|PUT|PATCH|DELETE)/{req=$0} /←/{req=""} END{if(req) print "Hung: " req}' \
  "tests/e2e/test-results/<run-dir>/api-log.txt"
```

### Compare timings across repeat runs

```bash
# Collect all response times for a specific endpoint across all retry dirs
grep "←.*POST.*login" tests/e2e/test-results/api-*/api-log.txt
```

### What `api-log.txt` contains vs what it does not

| Logged | Not logged |
|---|---|
| Every request URL + method + elapsed ms | Request headers (except in error bodies) |
| Every response status + round-trip ms | Full response bodies on 2xx |
| Full request + response bodies on 4xx/5xx | Playwright fixture setup/teardown steps |
| `[API Error]` prefix on non-2xx responses | Terminal assertion errors |

Full request + response bodies appear only for non-2xx responses. For a 200 response that returns unexpected data, you need to correlate with the Zod parse error in the terminal output and look at the schema in `tests/e2e/schemas/`.

---

## Phase 3 — Code investigation before acting

**Never claim a "Root Cause Hypothesis" without verifying it in the code.** Every hypothesis must include a file path, line number, and a code snippet. Ticket creation will not accept speculative claims as evidence.

### Standard investigation queries

#### Find the relevant service / controller

```bash
# Find files touching the failing domain
find <backend-dir>/app -name "*.php" | xargs grep -l "<keyword>" 2>/dev/null

# Find the frontend component
find <frontend-dir>/src -name "*.ts" -o -name "*.astro" | xargs grep -l "<keyword>" 2>/dev/null
```

#### Trace the data flow for a field value mismatch (UI)

1. Find the request validation class and the service class for the operation
2. Check what fields are required/optional — especially optional fields with defaults, `<tier-field>`, `<price-field>`
3. Check the fallback values on optional fields — `$field = $validated['field'] ?? '<default-value>'` is the first thing to look for
4. Check the repository's session-resolution method — does it create a new record after a transition? What defaults does the new record have?
5. Check the frontend payload in `<configurator-file>.ts` → the submit method → what optional fields does it include or omit?

#### Trace a timeout / error handling failure

1. Find `ApiClient.php` (the external API client) → check `->timeout()` and `->retry()` values
2. Check `throw: false` on retries — this silently swallows exceptions after N attempts
3. Check the controller `catch` block — does it pass `$e->getMessage()` to the response? Is it gated on `config('app.debug')`?
4. Check the frontend store — does it surface the `message` field from the 500 response to the UI?

#### Trace a stuck-button / race condition (UI)

1. Find the submit function in the main interactive component
2. Check when the in-progress state flag is set to `true` vs when `fetch()` is actually called — is there a window where an exception can escape the `finally` block?
3. Check for `AbortController` / `signal` on the `fetch()` call — absence means stalled TCP connections hang indefinitely
4. Check what other async functions mutate the same state (option callbacks, data fetchers, etc.) — look for concurrent mutation without a guard

#### Trace an API contract failure (API spec)

1. Read the Zod schema in `tests/e2e/schemas/<domain>.schema.ts` — which field failed validation and what type was expected vs received?
2. Find the Laravel controller + resource (`app/Http/Controllers/<domain>Controller.php` + `app/Http/Resources/`) — does the response shape match the schema?
3. Check `app/Services/<domain>/` for the method that builds the response — is there a field that is nullable in one code path but non-nullable in the schema?
4. If the `api-log.txt` shows a 4xx/5xx, check the `[API Error]` body for the exact Laravel error message, then grep `<backend-dir>/app` for that message string to locate the throw site.

### Code snippet format for the evidence package

Always include: file path + line range + the actual code. Use fenced code blocks with the language.

```
`<backend-dir>/app/Services/Api/ApiClient.php:68-74`:

```php
private function resilientRequest()
{
    return Http::withToken($this->getAccessToken())
        ->timeout(15)
        ->retry(3, 200, throw: false, when: function ($exception, $request) {
            return $exception instanceof \Exception;
        });
}
```
```

---

## Phase 4 — Acting on findings

After investigation, there are two failure root causes that require different actions:

### 4a — Test-side failure (bad selector, wrong assertion, fragile await)

Fix the test. No `.fixme()`, no ticket, no handoff. The test should pass once the test code is corrected.

### 4b — Code-side failure (app bug, API contract drift, external dependency misbehaving)

**Do not delete or silently comment out the test.** The test correctly identified a real problem. Order of operations:

1. **Assemble the evidence package** (see Phase 5). This is what ticket creation consumes.
2. **Hand off for ticket creation** — ticket creation owns ticket structure, scope, priority, labels, and the create call. It returns the created ticket URL.
3. **Mark the test with `test.fixme(true, '<reason>')`** using the returned ticket URL.
4. **Add the skill-reference comment** immediately above the `test.fixme(...)` call so the next contributor knows the workflow.

#### Why `test.fixme()` rather than `test.skip()`

- `test.fixme()` semantically means "this is broken and tracked"; reports surface it under a distinct status.
- `test.skip()` is the right tool when a test is **intentionally not applicable** (wrong env, wrong locale, feature flag off). Reach for it only when no underlying bug exists.
- Default for any RED-by-design test: `fixme`.

#### `.fixme()` annotation rules

Use `test.fixme(true, '<reason>')` — never the no-arg form.

The reason string must contain, in plain English:
- **What the actual failure is** — the concrete error or missing element
- **Why the app produces it** — the root cause in one sentence
- **The ticket URL returned by ticket creation** — so it's clickable from CI reports
- **What needs to happen before re-enabling** — concrete condition, usually "once the tracked ticket is resolved"

#### Annotation format

```typescript
// RED-by-design — tracked by ticket below.
// Workflow: see .claude/skills/playwright-debugging-and-reporting/SKILL.md
//          (Phase 4: collect evidence → hand off for ticket creation → fixme test)
test.fixme(
  true,
  '<what-fails> — <why-it-fails>. See <ticket-url>',
);
```

The two-line preamble comment above the call is **mandatory**. It serves two purposes:
- Surfaces the skill to anyone reading the spec, so they re-enter the workflow when the test status changes
- Makes the "RED by design" intent visible to reviewers — fixme is not failure, it's a tracked guard

#### Examples

```typescript
// RED-by-design — tracked by ticket below.
// Workflow: see .claude/skills/playwright-debugging-and-reporting/SKILL.md
test.fixme(
  true,
  'A third-party API returns {"success":false} for this <resource> — the dependent summary never renders. See <ticket-url>',
);

// RED-by-design — tracked by ticket below.
// Workflow: see .claude/skills/playwright-debugging-and-reporting/SKILL.md
test.fixme(
  true,
  'POST /api/<locale>/<resource>/items returns 422 {"message":"The <tier-field> field is required."} — the request validation class added a new required field not yet sent by the frontend component. See <ticket-url>',
);
```

**If the ticket does not exist yet** — hand off for ticket creation first. Filing the ticket before the fixme is part of the protocol; the fixme annotation must always carry a real URL, never a placeholder.

#### What NOT to write in `.fixme()` reasons

- `test.fixme(true, 'flaky')` — useless; says nothing about cause or fix
- `test.fixme(true, 'TODO: fix')` — not actionable
- `test.fixme(true, 'broken on CI')` — describes a symptom, not a cause
- Multi-sentence essays — one compound sentence is enough; the ticket holds the detail
- Missing the skill-reference comment — the comment is mandatory, even if the reason string is comprehensive

---

## Phase 5 — Hand off for ticket creation

This skill produces **facts and evidence**. Ticket creation produces **tickets**. The boundary is strict:

- This skill never decides: ticket title, priority, scope, labels, project, state, User Story wording, acceptance criteria, ticket template sections, or related-ticket links.
- This skill always provides: the raw failure evidence in a tight, copy-pasteable form.

Ticket creation is the source of truth for ticket structure.

### Evidence package — what to hand over

Assemble the following before handing off for ticket creation. Keep it tight; ticket creation arranges it into its own required sections.

- **Failure summary** — one paragraph: what breaks, under what condition, what the user sees. Include spec name, run count (e.g. "9/20 failures"), environment, locale, spec type (UI or API).
- **Error message** — exact terminal / `error-context.md` output, verbatim, in a code block.
- **Log evidence**
  - UI: only the relevant lines from `debug-log.txt` (Network Error, Slow Request, Navigation trail). Never paste the full log.
  - API: only the relevant `[API Error]` block from `api-log.txt` (request + response bodies). Never paste the full timeline.
- **Page state at failure** (UI only — omit for API findings) — only the 5–15 line excerpt from the page snapshot YAML showing the relevant element, URL, error paragraph, button state, or displayed value. Never paste the whole snapshot.
- **Code evidence** — one or more subsections, each with:
  - File path : line range
  - The actual code in a fenced block with the correct language tag
  - One sentence on why this is the problem
- **Funnel / endpoint impact** — which page or flow step (UI) or endpoint (API), affected locales / environments, user-facing UX consequence.
- **Fix direction** — concrete bullet list referencing the exact file and line to change. No speculation without code evidence.

### What this skill never produces

The following belong to ticket creation and must not be invented in the evidence package:

- Ticket title
- Priority rubric application
- Scope determination
- Label assignment
- User Story, acceptance criteria, and all ticket template sections
- Project, state, related-issue links, parent/child relationships
- Duplicate detection and plan-confirmation gating

Hand the evidence package over and let ticket creation compose. Do not pre-fill those fields, and do not duplicate them here.

### Classification hints for ticket creation

Ticket creation handles classification, but a clean failure-mode label helps it route correctly. From a single `--repeat-each` run, group distinct failure types — each distinct mode is its own ticket, not one ticket per run:

| Error pattern | Spec type | Likely failure category |
|---|---|---|
| `expect(received).toBe(expected)` with displayed values | UI | Field value mismatch — data or tier computed incorrectly |
| `TimeoutError: page.waitForURL` on `/<page-path>` | UI | Form submit blocked (external API timeout or version conflict) |
| `TimeoutError: locator.waitFor` on dynamic content element | UI | Dynamic content not loaded |
| `TimeoutError: page.waitForResponse` on `POST /<resource>/items` | UI | Submit request never dispatched (stuck button) |
| `locator.scrollIntoViewIfNeeded: Element is not attached to the DOM` | UI | DOM replaced mid-flight (navigation or re-render race) |
| `[API Error] POST /api/…/<resource>/items → 422` | API | Request validation rejection — field missing or invalid |
| `[API Error] GET /api/…/<resource>/… → 500` + external API error message | API | External API query failure — unindexed where-clause or projection timeout |
| Zod parse failure on a 200 response | API | Contract drift — API response shape diverged from schema |
| `429` on auth endpoint after retry budget exhausted | API | Rate limit exceeded — auth throttle too tight for parallel workers |

Hand ticket creation **one evidence package per failure mode**, not per run. Multiple runs with the same error belong in one package, which becomes one ticket.

### Evidence rules — what NOT to include

- **No artifact paths** (`tests/e2e/test-results/...`) — the directory is gitignored, paths are useless to a downstream reader. Embed the content directly.
- **No full page snapshots** — extract only the relevant 5–15 lines.
- **No full `[Timeline]` or `[API]` timeline dumps** — too noisy. Extract only the error lines and the 2–3 requests that immediately precede them.
- **No speculation without code evidence** — if you can't find the relevant code, say "not yet located" rather than guessing. Missing evidence may be downgraded or may block ticket creation; that's its decision to make.

### Handoff procedure

1. Compile the evidence package per the structure above.
2. Pass the evidence package to ticket creation. It discovers project/label/state context, runs duplicate detection, applies the priority rubric, sets scope, and confirms the plan before creating.
3. Wait for the ticket URL that ticket creation returns.
4. Return to Phase 4b step 3 and add the `.fixme()` annotation with that URL plus the skill-reference preamble comment.

---

## Example: full UI workflow

### Step 1 — run

```bash
cd tests/e2e && npx playwright test \
  specs/ui/<journey>/<spec-name>.spec.ts \
  --project=<ui-project> --repeat-each=20 --trace=on --workers=1
```

### Step 2 — triage

```bash
# Count artifacts to find failures
for dir in tests/e2e/test-results/<ui-project>-<spec-name>-*/; do
  count=$(ls "$dir" | wc -l | tr -d ' ')
  echo "$count $(basename $dir)"
done
# 4 = FAIL, 1 = pass

# Read error from first failure
awk '/^# Error details/,/^# Page snapshot/' \
  "tests/e2e/test-results/<ui-project>-<spec-name>-.../error-context.md"

# Check the network log for the root cause
grep "\[Network Error\]\|\[Network\] Request failed" \
  "tests/e2e/test-results/<ui-project>-<spec-name>-.../debug-log.txt"
```

Result: `Expected: "<expected-value>" / Received: "<actual-value>"` on `spec:<line>`. `debug-log.txt` shows no network errors — the submit request succeeded with a 200, so the mismatch is in the data, not the transport.

### Step 3 — investigate

```bash
# What does spec:<line> assert?
grep -n "<expected-value>\|<actual-value>\|Assert.*value" \
  "tests/e2e/test-results/.../error-context.md" | grep "|"
# → Assert <page> displayed value equals <record> field value

# What does the page snapshot show?
awk '/^# Page snapshot/,/^# Source/' error-context.md \
  | grep -i "<tier-field>\|paragraph\|<price-field>\|amount"
# → paragraph: <tier-value>  ← tier switched

# Find the service class
grep -n "<tier-field>\|<price-field>" \
  <backend-dir>/app/Services/<domain>/<domain>Service.php | head -20
# → $<tier-field> = $validated['<tier-field>'] ?? '<default-tier>';   ← line <line>
```

### Step 4 — assemble evidence package, hand off, then mark fixme

Root cause confirmed in app code → assemble the evidence package (failure summary, error message, log excerpt, page snapshot excerpt, code reference at `<service-class>.php:<line>`, funnel impact, fix direction), hand off for ticket creation, wait for the returned ticket URL, then add the fixme annotation referencing it.

```typescript
// RED-by-design — tracked by ticket below.
// Workflow: see .claude/skills/playwright-debugging-and-reporting/SKILL.md
test.fixme(
  true,
  'The displayed value does not match the expected field value — the service falls back to a default tier when the payload omits the field, changing the computed result. See <ticket-url>',
);
```

---

## Example: full API workflow

### Step 1 — run

```bash
cd tests/e2e && npx playwright test \
  specs/api/<domain>/<spec-name>.spec.ts \
  --project=api --repeat-each=10 --workers=3
```

### Step 2 — triage

```bash
# Find failed API runs (api-log.txt present in a retry dir)
ls tests/e2e/test-results/api-<spec-name>-*/api-log.txt

# Read all API errors from first failure
grep -A 15 "\[API Error\]" \
  tests/e2e/test-results/api-<spec-name>-<retry>/api-log.txt
```

Result: `[API Error] POST /api/<locale>/<resource>/items → 422` with body `{"message":"The <tier-field> field is required."}`.

### Step 3 — investigate

```bash
# Find the validation rule
grep -n "<tier-field>\|required" \
  <backend-dir>/app/Http/Requests/<domain>/<request-validator>.php

# Check the frontend payload builder (if this is also hit by UI tests)
grep -n "<tier-field>\|payload\." \
  <frontend-dir>/src/components/<component-dir>/<configurator-file>.ts | head -20
```

### Step 4 — assemble evidence package, hand off, then mark fixme

```typescript
// RED-by-design — tracked by ticket below.
// Workflow: see .claude/skills/playwright-debugging-and-reporting/SKILL.md
test.fixme(
  true,
  'POST /api/<locale>/<resource>/items → 422 {"message":"The <tier-field> field is required."} — the request validation class added a required rule not yet sent by the test fixture. See <ticket-url>',
);
```

---

## Common pitfalls

**Composing the ticket body inside this skill.**
This skill does not own ticket structure — ticket creation does. Writing a "Summary / User Story / Acceptance Criteria / Scope / Priority / Labels" section here duplicates and conflicts with ticket creation's responsibilities. Produce the evidence package; let ticket creation compose.

**Confusing `error-context.md` content with runtime console output.**
The file contains: error message, page snapshot YAML, spec source code. It does NOT contain `console.log` output from the test run. Runtime values are only in terminal stdout — if that was truncated, infer them from the snapshot or `debug-log.txt`.

**Ignoring `debug-log.txt` for UI failures.**
The page snapshot tells you *what was visible*. `debug-log.txt` tells you *what the network did*. A value mismatch with no `[Network Error]` lines means the HTTP request succeeded with wrong data — look at the payload. A value mismatch with a `[Network Error]` line means the request failed silently and a fallback value was used.

**Ignoring `api-log.txt` for API failures.**
The terminal assertion error tells you which field was wrong. The `api-log.txt` `[API Error]` block tells you what the server actually returned. Both are required for a complete evidence package.

**Handing off without reading the code.**
"Root cause: probably a race condition" with no code reference is useless. Every claim needs `file.php:line` evidence. If you can't find the code, say so in the evidence package rather than speculating — ticket creation's evidence gate handles unknowns.

**Pasting the full page snapshot or full log into the evidence package.**
The snapshot YAML is often 300+ lines. `api-log.txt` can be 500+ lines. Extract the 5–15 lines relevant to the failure. Ticket creation (and downstream readers) will not read full dumps.

**One handoff per run instead of one handoff per failure mode.**
If 4 out of 10 runs fail with the same 422 and 3 fail with a timeout, that is 2 evidence packages handed off, not 7.

**Referencing artifact paths in the evidence package.**
`tests/e2e/test-results/` is gitignored. Paths in tickets are dead links for everyone who wasn't running the tests. Embed the content, not the path.

**Using `test.fixme()` without a reason or without the skill-reference preamble.**
A bare `test.fixme()` leaves the next person with no idea why it was marked or how to re-enable it. Always use `test.fixme(true, '<reason>')` AND include the two-line preamble pointing back to this skill.

**Reaching for `.skip()` when `.fixme()` is right.**
`.skip()` is for tests that are intentionally not applicable (wrong env, feature flag off). For RED-by-design tests tracking a real bug, use `.fixme()` — the report distinction matters.

**Marking fixme before investigating.**
Never reach for `.fixme()` before confirming the root cause is in app code, not test code. A flaky selector or a missing `await` does not warrant a fixme — it warrants a fix.

**Filing the fixme before the handoff completes.**
The annotation must carry a real ticket URL returned by ticket creation. Hand off first, wait for the URL, then add the fixme. Placeholder fixmes ("ticket pending") drift into orphaned tests.
