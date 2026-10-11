---
name: playwright-deterministic-awaiting
description: "Apply deterministic waits and locator interactions in Playwright tests. Use whenever writing, fixing, or reviewing waits in the web app under test."
---

# Playwright — Deterministic Awaiting

> **Scope:** every test under `<e2e-dir>/`.
> Load whenever you write, fix, or review a wait or a locator interaction.
> Takes precedence over any generic waiting advice in `playwright-core` or `playwright-ui`.

## Placeholders

- `<e2e-dir>` — the folder that holds the end-to-end tests.
- `<action-endpoint>` — the API route that receives the action request.
- `<data-endpoint>` — the API route that returns data after a configuration change.

---

## Why this matters

The app is server-rendered: HTML arrives almost immediately from the server, while JavaScript hydrates stores and attaches event listeners asynchronously afterward. An element can be visible — even "enabled" — before its click handler exists. Generic `toBeVisible()` → `click()` works on static pages and breaks intermittently here.

The hierarchy below is strict. Pick the highest tier that applies.

---

## Hierarchy of waits — highest to lowest

### 1. Network response await (preferred when an action triggers a request)

Register the `waitForResponse` promise **before** the action. Playwright captures the response even if it resolves before you `await` the promise — but only if the listener was already in place.

```ts
// ✅ listener registered before the click
async clickAndCaptureResponse(actionButton: Locator, locale: string): Promise<Response> {
  const responsePromise = this.page.waitForResponse(
    (response) =>
      response.request().method() === 'POST' &&
      response.url().includes(`/api/${locale}/<action-endpoint>`),
    { timeout: 30_000 },
  );
  await actionButton.scrollIntoViewIfNeeded();
  await expect(actionButton).toBeEnabled({ timeout: 30_000 });
  await actionButton.click();
  return responsePromise;
}

// ✅ optional in-flight settle (when you don't need the response body)
async waitForDataSettled(locale: string): Promise<void> {
  await this.page.waitForResponse(
    (r) => r.url().includes(`/api/${locale}/<data-endpoint>`) && r.status() !== 0,
    { timeout: 2_000 },
  ).catch(() => { /* nothing in flight within 2s — already settled */ });
}

// ❌ listener AFTER the click — response may already be gone
await actionButton.click();
const response = await page.waitForResponse(/* ... */);
```

---

### 2. Application-state attribute (for JS-hydrated components)

Components signal readiness via `data-state` attributes set by their own code. Wait for the state attribute, not for visibility.

```ts
// ✅
async waitForWidget(): Promise<void> {
  await this.widget.waitFor({ state: 'visible', timeout: 30_000 });
  await this.widget.locator('[data-state="ready"]').waitFor({ state: 'visible', timeout: 30_000 });
}

// ❌ visible before JS hydration completes — click is swallowed
await expect(this.widget).toBeVisible();
await this.widget.getByRole('button').click();
```

Common `data-state` values:

| State | Meaning |
|---|---|
| `loading` | Waiting for initial data |
| `ready` | Hydrated and interactive |
| `idle` | Ready for input |
| `uploading` | Transfer in progress |
| `processing` | Server work in progress |
| `complete` | Done |
| `error` | Failed |

Each component defines which states it uses. Check its source before you wait on a state. Do not assume a page-wide "hydrated" attribute exists.

---

### 3. Actionability-gated click (for elements outside hydrated component trees)

`click()` performs its own actionability checks (attached, visible, stable, enabled, not obscured). For buttons outside hydrated trees, assert `toBeEnabled()` first when the button is in a managed loading/disabled state — that's the only pre-click assertion you need.

```ts
// ✅
await expect(this.submitButton, 'Submit button should be enabled before click').toBeEnabled();
await this.submitButton.click();

// ✅ fill() is already actionability-checked
await this.inputField.fill(inputValue);

// ❌ redundant toBeVisible() before click — does not help with hydration
await expect(this.submitButton).toBeVisible();
await this.submitButton.click();
```

---

### 4. `locator.waitFor({ state })` for late-arriving elements

Use when an element enters the DOM or becomes visible as a result of an async operation (response, store update, conditional render).

```ts
// ✅
await this.resultElement.waitFor({ state: 'visible' });
await this.actionButton.waitFor({ state: 'visible', timeout: 30_000 });

// ✅ race when either of two buttons may appear first
await Promise.race([
  this.primaryButton.waitFor({ state: 'visible', timeout: 30_000 }),
  this.stickyButton.waitFor({ state: 'visible', timeout: 30_000 }),
]);

// ❌ forbidden everywhere
await page.waitForTimeout(2000);
```

---

### 5. `expect.toPass()` — third-party iframes only

Cross-origin iframes' internal requests cannot be reliably intercepted. Retry the assertion until it passes.

**Scope:** third-party embeds only. Don't paper over hydration races in first-party code with `toPass()` — fix the wait strategy.

---

## What is forbidden everywhere

| Pattern | Why |
|---|---|
| `await page.waitForTimeout(N)` | Arbitrary sleep |
| `const v = await locator.isVisible(); expect(v).toBe(true)` | Doesn't auto-poll |
| `await expect(el).toBeVisible(); await el.click()` | `toBeVisible()` doesn't guarantee handlers are attached |
| Helpers that wrap `click()` with `toBeVisible()` / `toBeEnabled()` | `click()` already performs actionability checks |
| `waitForResponse` registered AFTER the trigger | Listener may miss the response |
| `expect.toPass()` for first-party API-backed code | Use `waitForResponse` |
| `waitUntil: 'networkidle'` in `page.goto()` | Modern web apps rarely reach network idle inside the timeout. Use `'load'` or `'domcontentloaded'` plus a state-based wait. |

---

## Iframe interactions

> If the project uses third-party tools of this kind, update this skill to handle them. If it does not, skip this instruction.
