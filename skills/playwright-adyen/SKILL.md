---
name: playwright-adyen
description: Locator structure and interaction rules for the Adyen Web Drop-in card form in Playwright tests. Use whenever a UI test fills, asserts, or otherwise interacts with Adyen's Secured Fields, the pay button, or any Adyen iframe.
---

# Playwright — Adyen Web Drop-in

> **Scope:** every UI test that touches the Adyen Drop-in, such as payment interaction specs under `<e2e-dir>/specs/`.
> **Loads alongside `playwright-ui` and `playwright-deterministic-awaiting`** — Adyen-specific rules in this file take precedence over generic iframe / locator advice elsewhere.
> **Source of truth:** `<e2e-dir>/components/AdyenPayment.ts`. If anything below conflicts with that file, the file wins.

## Placeholders

- `<e2e-dir>` — root folder of the end-to-end test project; it holds the shared page components, the fixtures and the specs.
- `<spec-file>` — path of a single spec file to run.
- `<headed-test-command>` — the command that runs one spec file in a visible browser.
- `<locale-env-var>` — the environment variable that selects the locale for a test run.
- `<payment-page-path>` — URL path of the page that renders the Adyen Drop-in, including any locale prefix.

---

## Why Adyen needs its own skill

The Adyen Web Drop-in is a third-party UI rendered inside the page. Three things make it different from anything else we test:

1. **Cross-origin iframes.** Card number, expiry, and CVC each render in an iframe served from `checkoutshopper-test.adyen.com`. We cannot intercept the iframe's internal requests, instrument its hydration, or read its store state.
2. **Locale-translated `title` attributes.** Adyen translates iframe `title` per locale ("Iframe for card number" → "Iframe voor kaartnummer"). Any test that scopes by `title` works on `en-gb` and silently breaks on every other locale.
3. **Hydration races.** The iframe element appears in the parent DOM before the iframe document is ready to accept input. A naive `toBeVisible() → fill()` flake-loops on staging.

The fixes for these three live in `<e2e-dir>/components/AdyenPayment.ts`. Use that file. Don't roll your own.

---

## The `data-cse` attribute is on the WRAPPER, not the iframe

This is the rule that catches everyone exactly once. Read it before you write a line.

The Adyen 4.x rendered DOM looks like this:

```html
<span data-cse="encryptedCardNumber" data-uid="adyen-checkout-encryptedCardNumber-…" class="adyen-checkout__input …">
  <iframe
    src="https://checkoutshopper-test.adyen.com/…/securedFields.html?type=card…"
    class="js-iframe"
    title="Iframe for card number"
    allowtransparency="true">
    <p>Your browser does not support iframes.</p>
  </iframe>
</span>
```

The `data-cse` attribute is on the **`<span>` parent**, NOT on the `<iframe>` element.

Therefore:

| Selector | Matches? | Use? |
|---|---|---|
| `iframe[data-cse="encryptedCardNumber"]` | ❌ zero matches | **Forbidden — common mistake** |
| `[data-cse="encryptedCardNumber"] iframe` | ✅ exactly one | **Required** |
| `iframe[title="Iframe for card number"]` | ✅ on `en-gb` only | **Forbidden — locale-bound** |

The descendant selector is locale-agnostic (the wrapper's `data-cse` is a stable Adyen identifier, not a translated string) AND topologically correct.

---

## The four Adyen identifiers used today

| Adyen field | `data-cse` value | Selector to use |
|---|---|---|
| Card number | `encryptedCardNumber` | `[data-cse="encryptedCardNumber"] iframe` |
| Expiry date | `encryptedExpiryDate` | `[data-cse="encryptedExpiryDate"] iframe` |
| Security code (CVC) | `encryptedSecurityCode` | `[data-cse="encryptedSecurityCode"] iframe` |
| Card holder name | (not an iframe) | `[autocomplete="cc-name"]` |

The card holder name is a regular HTML `<input autocomplete="cc-name">` rendered in the parent document — no iframe, no encryption widget. Scope by `autocomplete="cc-name"` (a standard HTML attribute, locale-stable).

The pay button:
- `.adyen-checkout__button--pay` — Adyen's own CSS class. Stable across versions and locales.

---

## Iframe interaction is wrapped in `expect.toPass()`

Adyen's iframe document hydrates after the iframe element is attached. A direct `toBeVisible()` on a textbox inside the iframe will pass while the iframe is still loading internally, and the subsequent `fill()` then races. We can't intercept the iframe's internal load events because they're cross-origin.

The remedy is `expect.toPass()` — Playwright's retry primitive — wrapping the visibility assertion. It re-runs the inner assertion until it succeeds or the outer timeout expires. Each retry resolves the textbox locator from scratch, which forces a fresh iframe-content lookup.

Reference: `<e2e-dir>/components/AdyenPayment.ts → waitForFrameInput()`:

```ts
private async waitForFrameInput(frame: FrameLocator, label: string): Promise<Locator> {
  let input: Locator | undefined;
  await expect(async () => {
    input = frame.getByRole('textbox');
    await expect(input, `${label} should be visible inside Adyen iframe`).toBeVisible({
      timeout: 5_000,
    });
  }).toPass({ timeout: 30_000 });
  return input!;
}
```

`expect.toPass()` is **the only acceptable** wait pattern for first interaction with an Adyen iframe. Do not substitute `waitFor()`, `waitForLoadState()`, or `waitForTimeout()`.

After the input is resolved once, subsequent `.fill()` / `.press()` calls on the same `Locator` work without further wrapping.

---

## How to add a new Adyen field interaction

You are extending `AdyenPayment.ts` (e.g. adding 3DS challenge code entry, an alternative payment method, a brand-specific holder field). Follow this workflow:

1. **Render the page in a real browser** with the relevant Adyen Drop-in configuration. Use the staging or local stack — don't guess from Adyen documentation alone (Adyen's docs lag the rendered markup).
2. **Open DevTools → Elements** and find the field you want to interact with.
3. **Identify what kind of element it is:**
   - Iframe-wrapped (Secured Field): walk up to the nearest ancestor with `data-cse="…"`. That value is your locale-agnostic identifier. Use `[data-cse="<value>"] iframe`.
   - Plain `<input>` in the parent document: prefer `autocomplete="…"` if Adyen sets it (standard HTML, locale-stable). Otherwise use the `name` attribute or a stable `data-*` Adyen-emitted attribute. Never use the visible `<label>` text — Adyen translates labels.
   - Adyen button: prefer `.adyen-checkout__button--<role>` (`--pay`, etc.). These class names are stable across Adyen versions.
4. **Dump the rendered HTML and grep for the attribute** to confirm uniqueness on the page:

   ```bash
   curl -sL https://localhost/<payment-page-path> \
     | grep -E 'data-cse|autocomplete="cc-' \
     | head -20
   ```

   If the attribute appears more than once (e.g. wrapped in a hidden alternative payment-method panel), narrow the scope by combining with a parent selector or `:visible`.
5. **Add a `FrameLocator` or `Locator` field** to `AdyenPayment` using the patterns above.
6. **Wrap the first interaction in `expect.toPass()`** via `waitForFrameInput()`. Plain inputs in the parent document don't need `toPass` — a regular `await expect(input).toBeVisible()` is fine.
7. **Verify locally** by running the spec headed once: `<headed-test-command> <spec-file>`. If it works locally on `en-gb`, **also run once with `<locale-env-var>=nl-nl`** before declaring done — that is where the `title`-based locale traps surface.

---

## Forbidden patterns

| Pattern | Why |
|---|---|
| `frameLocator('iframe[data-cse="encryptedCardNumber"]')` | `data-cse` is on the wrapper `<span>`, not the iframe. Matches zero elements. |
| `frameLocator('iframe[title="Iframe for card number"]')` | `title` is translated by Adyen per locale. Passes on `en-gb`, fails on every other locale. |
| `getByLabel('Card number')` | Label text is translated. Same problem as `title`. |
| `getByRole('textbox', { name: 'Card number' })` | `name` resolves from the translated label. |
| Direct `frame.getByRole('textbox').fill(value)` without `expect.toPass()` first | Races the iframe's cross-origin hydration. Flakes on staging. |
| `await page.waitForTimeout(2000)` to "wait for Adyen" | Forbidden everywhere — see `playwright-deterministic-awaiting`. |
| Mocking the Adyen drop-in via `page.route('**/adyen.com/**', …)` for a happy-path test | Defeats the purpose. Reserved for explicit Adyen-failure simulation specs. |

---

## Reference implementation

`<e2e-dir>/components/AdyenPayment.ts` is the single source of truth. Read it before extending.

Fixture: `adyenPayment`, defined in the fixtures folder under `<e2e-dir>/fixtures/`. Always declare the fixture in your test parameters — never `new AdyenPayment(page)` inside a test body.

---

## Checklist (writing or extending Adyen interactions)

- [ ] Iframe scoping uses `[data-cse="…"] iframe` — never `iframe[data-cse="…"]` and never `iframe[title="…"]`.
- [ ] Plain inputs use `autocomplete="…"` or a stable Adyen `data-*` attribute. No translated text.
- [ ] First interaction with each iframe goes through `waitForFrameInput()` (or an equivalent `expect.toPass()` wrapper).
- [ ] Component lives in `<e2e-dir>/components/AdyenPayment.ts`. Spec instantiates via the `adyenPayment` fixture.
- [ ] Verified locally on `en-gb` AND at least one non-English locale (`nl-nl` / `de-de` / `fr-fr`) before merge.
- [ ] No `page.waitForTimeout()`. No `page.route('**/adyen.com/**', …)` outside an explicit Adyen-failure spec.
