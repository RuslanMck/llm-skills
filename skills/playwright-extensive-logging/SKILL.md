---
name: playwright-extensive-logging
description: "Understand, extend, or troubleshoot the buffered Playwright E2E logging and test-result attachment system."
---

# Playwright Extensive Logging

How the E2E logging system works, what it captures, and how to extend or reconfigure it.

**Placeholders** (map each to your own project's value):
- `<staging-host>` — the host the E2E suite runs against
- `<locale>` — the locale segment of your site's URL paths
- `<suite>` — the name of a Playwright test suite or project
- `<test-name>` — the title-derived directory name of a single test

## Overview

All logging in the E2E suite is **buffered and always-attached**. Event listeners collect log lines into an in-memory `TestLogger` buffer during the test. At teardown, the buffer is written to a `.txt` attachment via `testInfo.attach()` on every run — including retries that eventually pass — so no diagnostic information is silently discarded.

This means:
- Zero CI console noise (logs go to files, not stdout)
- Full diagnostic detail available as a downloadable artifact under `test-results/`
- Retry failures always produce their own log file
- No large HTML report — CI uses the `line` reporter only (see `playwright.config.ts`)

---

## Three layers of logging

### Layer 1 — Base `page` fixture (`ui-fixtures.ts`)

Active for **every UI test** that uses the `page` fixture from `ui-fixtures.ts`.

Captures browser, page-lifecycle events, and full network monitoring:

| Event | Log prefix | What it records |
|---|---|---|
| `page.on('console')` | `[Browser] console.<type>:` | All browser console output — log, info, warn, error, debug |
| `page.on('framenavigated')` | `[Navigation] →` | Every main-frame URL change, including redirects |
| `page.on('requestfailed')` | `[Network] Request failed —` | Own-origin requests that fail at network level (DNS, ERR_FAILED, etc.) |
| `page.on('crash')` | `[pw:crash]` | Page process crash with last known URL |
| `page.on('close')` | `[pw:close]` | Unexpected page close with last known URL |
| `page.context().on('close')` | `[pw:context-close]` | Unexpected browser context close |
| `attachRequestTimeline` | `[Timeline]` | Every own-origin request/response with elapsed ms |
| `monitorNetworkErrors` | `[Network Error]` | 4xx/5xx responses with full request + response bodies |
| `monitorSlowRequests` | `[Slow Request]` | Requests exceeding 30s with bodies |

`pageerror` (uncaught JS exceptions) is **not buffered** — it collects into a separate `unhandledErrors` array and throws after `use()`, which always surfaces as a test failure regardless of other outcomes.

**Output file:** `debug-log.txt` — attached to the test in `test-results/` on every run.

```
[Navigation] → https://<staging-host>/<locale>/
[Browser] console.log: [app] item loaded — 0 results
[Timeline] +312ms     →  GET /<locale>/
[Timeline] +891ms     ←  200 GET /<locale>/
[Network] Request failed — GET https://<staging-host>/api/<locale>/<resource> — net::ERR_CONNECTION_REFUSED
[Network Error] POST https://<staging-host>/api/<locale>/<resource> → 422
  Request body:
  {"id":"abc123"}
  Response body:
  {"message":"Validation failed","code":"VALIDATION_ERROR"}
```

---

### Layer 2 — `request` fixture (`api-fixtures.ts`)

Active for **every API test** that uses `request`-based service fixtures from `api-fixtures.ts` (all API specs).

Wraps `APIRequestContext` with a `Proxy` that intercepts HTTP method calls and logs:
- Timeline line for every request/response with elapsed ms and round-trip duration
- Full request + response bodies only for 4xx/5xx responses

**Output file:** `api-log.txt` — attached to the test in `test-results/` on every run.

```
[API] +12ms     →  POST /api/<locale>/auth/register
[API] +487ms    ←  201 POST /api/<locale>/auth/register (475ms)
[API] +490ms    →  POST /api/<locale>/auth/login
[API] +612ms    ←  429 POST /api/<locale>/auth/login (122ms)
[API Error] POST /api/<locale>/auth/login → 429
  Request body:
  {
    "email": "user@example.com",
    "password": "..."
  }
  Response body:
  {"message":"Too Many Requests"}
```

---

## Private helpers

`TestLogger` (`tests/e2e/helpers/testLogger.ts`) owns the buffer + flush policy. The fixture infrastructure owns only the wiring (what to log and when to flush).

Three exported functions in `ui-fixtures.ts` that the base `page` fixture wires automatically:

| Helper | Purpose |
|---|---|
| `attachRequestTimeline(page, ownOrigin, log)` | Logs every own-origin request/response with elapsed ms |
| `monitorNetworkErrors(page, log)` | Logs 4xx/5xx responses with full bodies |
| `monitorSlowRequests(page, log, thresholdMs)` | Logs slow requests (default: 30s) |

Shared utilities in `tests/e2e/helpers/networkUtils.ts`:

| Helper | Purpose |
|---|---|
| `pathOf(url)` | Extracts `pathname + search` from a URL string for compact log lines |
| `bodyPreview(raw)` | Single-line body snippet truncated at 300 chars |
| `readBodies(request, getResponseText)` | Reads and prettifies request + response bodies; inner read is best-effort |

`prettifyBody` lives in `tests/e2e/helpers/prettifyBody.ts` — attempts `JSON.parse` + `JSON.stringify` for readable indentation, falls back to the raw string.

---

## CI artifact layout

On every run, `test-results/` contains per-test subdirectories:

```
test-results/
  ui-<suite>-<test-name>/
    debug-log.txt       ← base page fixture (browser/nav/network events + timeline)
    trace.zip           ← Playwright trace (step-by-step with DOM snapshots)
    screenshot.png      ← screenshot at point of failure
    video.webm          ← full test video
  api-<test-name>/
    api-log.txt         ← API request fixture (timeline + errors for 4xx/5xx)
```

The `playwright-test-results-<suite>` artifact in GitHub Actions includes all of these. Download it from the Actions run page → Artifacts.

---

## How to extend or reconfigure

### Change the slow request threshold

In `ui-fixtures.ts`, `monitorSlowRequests` defaults to 30s. Edit the call in the base `page` fixture:

```ts
monitorSlowRequests(page, logger.log);           // 30s default
monitorSlowRequests(page, logger.log, 10_000);   // override to 10s
```

### Add a new event to the base page fixture

Add a listener inside the base `page` fixture in `ui-fixtures.ts` and call `logger.log(...)`:

```ts
page.on('dialog', (dialog) => {
  logger.log(`[Dialog] ${dialog.type()}: ${dialog.message()}`);
  dialog.dismiss();
});
```

### Change the body preview truncation length

`bodyPreview` in `helpers/networkUtils.ts` hardcodes 300 chars. Edit the constant directly.

---

## Reporter configuration

Configured in `tests/e2e/playwright.config.ts`:

```ts
reporter: process.env.CI
  ? [['line']]   // CI: plain text, one line per test, failures in full at the end
  : [
      ['html', { open: 'never', outputFolder: '...' }],  // local: interactive report
      ['list'],                                            // local: live terminal output
    ],
```

`html` reporter is intentionally excluded from CI — it produces very large artifacts by inlining traces and video as base64. The `line` reporter combined with the `debug-log.txt` / `api-log.txt` attachments is sufficient for diagnosing failures.
