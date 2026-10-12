---
name: playwright-locators
description: data-testid conventions for Astro components — covers writing new code AND auditing existing files. Apply to every .astro / .ts file the AI touches.
---

# Playwright Locators — `data-testid` Strategy

Two modes, one rulebook:

- **Writing new code** — every interactive element gets a `data-testid` before the file is closed.
- **Auditing existing code** — find elements without a `data-testid`, propose fixes, apply them additively.

## Placeholders

- `<app-dir>` — the frontend app folder: the directory that contains `src/` (pages, components, lib, stores).
- `<locales-file>` — the file that lists the supported locales. It is the single source of truth.
- `<locale>` — any supported locale code, used in URLs.
- `<service-name>` — the app's service name in the local container stack.
- `<proxy-service>` — the reverse-proxy service in the local container stack.
- `<header-component>` — the component file that renders the site header and search.
- `<i18n-file>` — the translation helper file, e.g. `src/lib/i18n.ts`.

---

The app is multi-locale (the `LOCALES` array in `<locales-file>` is canonical). Visible text comes from `t(locale, 'key')` in `<i18n-file>` and changes per language. Text-based locators break on non-English locales. **`data-testid` is the only stable locator.**

The frontend stack is Astro SSR + vanilla TypeScript. Stores are module singletons — they are NOT on `window`. Both static SSR markup and JS-hydrated panels get the same `data-testid` treatment.

---

## Locator priority (test-side)

| Priority | Locator | When |
|---|---|---|
| 1 | `getByTestId()` | Default for every interactive element. Always add `data-testid`. |
| 2 | `getByRole()` (no `name`) | Narrowing inside a testid scope, e.g. `getByTestId('login-form').getByRole('button')` |
| 3 | CSS / attribute | Last resort — third-party widgets without testid hooks. > If the project uses third-party tools of this kind, update this skill to handle them. If it does not, skip this instruction. |
| ❌ | `getByText`, `getByLabel`, `getByPlaceholder`, `getByRole({ name })` | Forbidden — all locale-bound. |

---

## Naming convention

**Format:** `{area}-{element}-{identifier?}` — kebab-case only.

| Pattern | Example |
|---|---|
| Page section / container | `hero-section`, `sidebar-panel` |
| Button / CTA | `hero-submit`, `sidebar-apply-btn` |
| Form field | `login-email`, `contact-phone` |
| SSR repeated item | `list-item-{id}` |
| Client-side repeated item | `result-item-{id}`, `result-item-{id}-remove` |
| Modal / dialog | `confirm-dialog`, `preview-modal` |
| Navigation | `main-navigation`, `breadcrumb`, `mobile-menu` |
| Reactive store panel | `sidebar-panel`, `search-overlay` |

### Page-area prefixes

> Populate this table with your project's page areas. The entries below are illustrative; replace or extend them to match your app's structure.

| Area | Prefix |
|---|---|
| Header / top nav | `header-` |
| Mobile menu | `mobile-menu-` |
| Search | `search-` |
| Login / Register | `login-`, `register-` |
| User account | `account-` |
| Footer | `footer-` |

**Rules:**
- Kebab-case only — no camelCase, no underscores.
- Use stable domain IDs for repeated items, never array indices.
- Never duplicate a value on the same page.
- **Never** append viewport modifiers (`-mobile`, `-desktop`). Tailwind handles visibility — tests use `.locator(':visible')`.

---

## Rules by element type

### Buttons — every `<button>` needs a testid

```astro
<!-- ✅ -->
<button type="submit" class="btn btn-primary" data-testid="hero-submit">
  {t(locale, 'hero.submit')}
</button>

<!-- ✅ icon-only — keep aria-label for users -->
<button type="button" class="btn btn-icon"
        data-testid="sidebar-close"
        aria-label={t(locale, 'sidebar.close')}>
  <svg>...</svg>
</button>

<!-- ❌ no testid, text is translated -->
<button type="submit">{t(locale, 'hero.submit')}</button>
```

### Form controls

Every `<input>`, `<select>`, `<textarea>` needs a testid. Keep `<label for="">` for accessibility.

```astro
<label for="login-email">{t(locale, 'auth.email')}</label>
<input type="email" id="login-email" name="email" data-testid="login-email" />
```

Dynamic field names:

```astro
<input type="text"
       id={`address-${field}`}
       name={field}
       data-testid={`address-${field}`} />
```

### Links — CTAs and navigation links only

```astro
<a href={`/${locale}/search`}
   data-testid="header-search-link"
   aria-label={t(locale, 'nav.search')}>
  <svg>...</svg>
</a>
```

### `.map()` SSR loops — stable domain ID, never index

```astro
{items.map((item) => (
  <div class="list-item" data-testid={`list-item-${item.id}`}>
    <a href={item.url} data-testid={`list-item-${item.id}-link`}>
      {item.name}
    </a>
  </div>
))}
```

### Modals / dialogs

```astro
<div role="dialog"
     data-testid="confirm-dialog"
     aria-labelledby="confirm-title"
     data-modal="confirm">
  <h2 id="confirm-title">{t(locale, 'dialog.confirm_title')}</h2>
</div>
```

### Reactive-store-driven panels

The store is a module singleton, NOT on `window`. The `data-testid` lives on the HTML element regardless:

```astro
<div data-testid="sidebar-panel" data-sidebar-panel>
```

---

## Audit mode — finding gaps in existing files

When auditing a file or page flow:

1. Read every interactive element. Bucket by severity:
   - **Missing** — element has no `data-testid` at all.
   - **Weak** — element only targetable via translated text, Tailwind class, or DOM position.
   - **OK** — has a `data-testid` matching the convention.
2. Report each issue as `file:line — element type — proposed testid`.
3. Page-flow audits — update the table below with your project's key flows and their source files, then start from those entry points:

   | Flow | Files |
   |---|---|
   | Login / Register | `<app-dir>/src/pages/[locale]/login.astro` |
   | Search | `<app-dir>/src/pages/[locale]/search.astro`, `<app-dir>/src/components/search/`, `<app-dir>/src/components/<header-component>` |
   | Account | `<app-dir>/src/pages/[locale]/account/` |

---

## Applying fixes — additive only

- **Never** rename or remove an existing `id`, `class`, `data-*`, `x-*`, or event attribute.
- **Never** restructure HTML or move elements. Only add the `data-testid` (and missing `aria-*` if the audit also flagged accessibility gaps).
- **Never** replace `t(locale, '...')` calls with hardcoded strings.
- **Never** touch `node_modules/`, `dist/`, `.astro/`, or third-party widget markup.

If an audit finds an interactive element without a stable testid AND the AI is in the middle of writing a Playwright test, **stop and notify**:

> ⚠️ Missing `data-testid`: `<element>` in `<Component>.astro` has no `data-testid`. The test cannot be written in a locale-agnostic way until one is added. Add the attribute following the naming convention above before continuing.

Do not work around it with text/CSS/XPath fallbacks.

---

## Accessibility (separate concern, both still required)

`data-testid` is for tests. Keep accessibility too:

- `aria-label` on icon-only buttons/links — translated via `t(locale, ...)`.
- `<label for="">` on every form control.
- `role="dialog"` + `aria-labelledby` on modals.
- Semantic HTML (`<nav>`, `<h1>`–`<h6>`, `<button>`, `<main>`).
- `aria-expanded` on toggles, set from vanilla TS.

---

## After editing `.astro` markup — rebuild the local stack

The app container is built from source; rebuild and restart it after every markup change so the new attributes show up in the rendered DOM.

```bash
docker compose build <service-name>
docker compose up -d <service-name>
docker compose restart <proxy-service>   # only if the proxy returns 502 after recreate
curl -sL http://localhost/<locale>/ | grep 'data-testid'
```

---

## Checklist (writing or auditing)

- [ ] Every `<button>`, `<a>` (CTA/nav), `<input>`, `<select>`, `<textarea>` has `data-testid`.
- [ ] SSR `.map()` items use a stable domain ID — never the array index.
- [ ] Modals/dialogs have `data-testid` + `role="dialog"` + `aria-labelledby`.
- [ ] `data-testid` follows `{area}-{element}-{id?}` and uses an allowed area prefix.
- [ ] No duplicate `data-testid` on the same page.
- [ ] No viewport modifier (`-mobile`, `-desktop`) on any `data-testid`.
- [ ] No element relies on Tailwind class, `x-ref`, or DOM position to be targetable.
- [ ] Accessibility attributes (`aria-label`, `<label>`, `aria-expanded`, semantic HTML) are present.
- [ ] App container rebuilt + restarted after `.astro` markup changes.
