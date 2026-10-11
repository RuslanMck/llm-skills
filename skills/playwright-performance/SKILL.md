---
name: playwright-performance
description: "Author and maintain synthetic Core Web Vitals tests (Playwright + Lighthouse) under <perf-specs-dir> — thresholds, emulation profiles, median-of-runs measurement, fixme-on-red workflow. Use when touching perf specs, adding Lighthouse assertions, or answering CWV-gate / 'why is LCP failing' questions."
---

# Playwright Performance — Core Web Vitals Gates

> **Scope:** every test under `<perf-specs-dir>`.
> **Load alongside `playwright-core` and `playwright-ui`** — directory layout, env config, tagging, fixture conventions, `test.step()` rules all live there. This file covers only the performance-specific delta.
> **Source of truth:** `<e2e-dir>/playwright.config.ts` (the `perf` project block), `<perf-helper-file>`, `<thresholds-file>`. If anything below conflicts with the code, the code wins.

## Placeholders

Map each placeholder to the same role in your own repo before using this skill:

- `<e2e-dir>` — root folder of the end-to-end test suite; holds the Playwright config.
- `<perf-specs-dir>` — folder for performance specs, a sub-folder of `<e2e-dir>` (e.g. `specs/perf/`).
- `<area>` — folder name and tag prefix for one page area (e.g. `home`, `about`).
- `<perf-helper-file>` — the single module that wraps Lighthouse runs (`runLighthouse`).
- `<thresholds-file>` — the module holding the numeric thresholds. Every number in this skill lives there, never here.
- `<routes-file>` — the registry of routes per page area.
- `<perf-results-dir>` — where per-run JSON and HTML reports are written.
- `<perf-ci-workflow>` — the CI workflow that runs perf tests on a schedule or on demand.
- `<perf-test-command>` — the command that runs only the perf project.
- `<fixtures-module>` — the module that re-exports `test` and `expect` for the suite.
- `<layout-file>` — the shared page layout that loads global styles.
- `<ticket-prefix>` — the issue-tracker key prefix for perf tickets.
- `<perf-plan-doc>` — the implementation plan for the perf suite, if one exists.
- `<run-count>` — the number of Lighthouse runs per measurement, as set in `<perf-helper-file>`.
- `<measured>` / `<threshold>` — a measured value and the threshold it was compared against, in a ticket or fixme message.
- `<run-values>` — the individual run results, listed in a ticket or fixme message.
- `<top-audit>` / `<savings>` — the top contributing Lighthouse audit and its estimated saving, from the report.
- `<perf-timeout>` — the per-test timeout for the perf project, long enough for several Lighthouse runs.

---

## Why this matters

Core Web Vitals are a release gate, not a cosmetic concern. They feed search ranking (Google Page Experience) and user experience, so a route that regresses on them affects organic reach.

This skill is the test-side enforcement of that gate. A failing route is not shipped, and there is no per-locale or per-route exception.

---

## Industry standards — the metrics we gate on

The thresholds in `<thresholds-file>` are derived from Google's published Core Web Vitals targets and the Lighthouse scoring curve. **Do not change them without a written rationale referencing the upstream standard.** This section names the metrics and what each one measures; the numbers belong to `<thresholds-file>`.

### Core Web Vitals — the three Google ranks on

| Metric | What it measures | Source |
|---|---|---|
| **LCP** (Largest Contentful Paint) | Loading speed of the main content | [web.dev/lcp](https://web.dev/lcp/) |
| **CLS** (Cumulative Layout Shift) | Visual stability while the page loads | [web.dev/cls](https://web.dev/cls/) |
| **INP** (Interaction to Next Paint) | Responsiveness to user input | [web.dev/inp](https://web.dev/inp/) |

INP **replaced FID** as a Core Web Vital. Never assert on FID; never write `firstInputDelay` in new code.

### Supplementary Lighthouse metrics (lab proxies)

These don't determine ranking directly but they're what Lighthouse measures in the lab — they're the operational signals we gate on.

| Metric | What it measures |
|---|---|
| **FCP** (First Contentful Paint) | When the first content appears |
| **TBT** (Total Blocking Time) | Main-thread blocking; the lab proxy for INP |
| **SI** (Speed Index) | How quickly the visible page fills in |
| **Performance score** (overall) | Lighthouse's weighted score across the metrics above |

The overall score gate is set in `<thresholds-file>`. Tighten it only after the process in "Where threshold tightening IS allowed" below.

### TTI is dead, don't use it

Time to Interactive was fully removed from Lighthouse. New tests **never** assert on TTI.

### Field data (CrUX) vs lab data (Lighthouse)

| | Field (CrUX) | Lab (Lighthouse) |
|---|---|---|
| **Source** | Real Chrome users, opted into CrUX | Synthetic Chromium run in CI |
| **Aggregation** | P75 over a rolling window per origin | Single (or median-of-runs) snapshot |
| **Authority** | What Google uses for ranking | Proxy — does not determine ranking |
| **What this suite measures** | ❌ no (out of scope) | ✅ yes (every nightly) |

The CWV KPI (a P75 pass rate on mobile) is a **field-data** target measured against production CrUX. This synthetic suite is the **leading indicator**: a clean Lighthouse nightly does not guarantee a clean CrUX P75, but a failing Lighthouse nightly virtually guarantees a failing CrUX P75. Use the suite as the early-warning system, not the certifying authority. Real-user monitoring (web-vitals package emitting to a backend) is out of scope for the suite and is a separate follow-up initiative.

### Lighthouse emulation calibration

The Lighthouse default mobile preset (the one we use, the one Google uses for PageSpeed Insights) emulates a slow mobile network, a throttled mid-tier device and a phone-sized viewport. The default desktop preset emulates a fast wired connection, an unthrottled CPU and a desktop viewport. The exact values are Lighthouse's own, and they are not overridden in this suite.

**Never override the throttling preset to make a test pass.** That isn't measuring the same thing as PageSpeed Insights / CrUX and decouples the lab signal from the field reality.

---

## The `perf` Playwright project

```ts
// playwright.config.ts (excerpt)
{
  name: 'perf',
  testMatch: /<perf-specs-dir>\/.*\.spec\.ts$/,
  workers: 1,            // Lighthouse cannot run in parallel against the same target — metrics skew
  timeout: <perf-timeout>, // several Lighthouse runs plus overhead
  retries: 0,            // a flaky perf result is signal; retry would mask regressions
  use: {
    storageState: { cookies: [], origins: [] },  // clean session per test
    extraHTTPHeaders: stagingBypassHeaders,
  },
}
```

**Hard rules for the `perf` project:**

- `workers: 1` is non-negotiable. Two Lighthouse runs against the same staging origin contaminate each other's CPU/network measurements.
- `retries: 0`. Lighthouse already does its own retries internally if a metric is unrecoverable; Playwright retries on top would only mask flake.
- Excluded from the default e2e run. Lighthouse is slow; running it on every PR-gate run wastes CI minutes. Triggered explicitly via `<perf-test-command>` or `<perf-ci-workflow>`.
- Never share storageState with authenticated Playwright projects. Authenticated sessions skew SSR cache hit rates and produce non-representative LCP numbers.

---

## The Lighthouse helper — `<perf-helper-file>`

All perf specs go through one helper. Spec files never construct a Lighthouse run inline.

```ts
import { runLighthouse } from '<perf-helper-file>';

test('home page mobile CWV thresholds', async ({ baseURL, locale }) => {
  // No `page` — the helper launches its own Chrome via chrome-launcher to
  // avoid the CDP conflict with Playwright's request-interception layer,
  // which aborts navigations.
  const fullUrl = new URL(uiPath(locale, '/'), baseURL).toString();
  const result = await runLighthouse(fullUrl, {
    device: 'mobile',
    runs: <run-count>,
    name: 'home',
  });

  await test.step(`Performance score meets the threshold (measured: ${result.performanceScore})`, () => {
    expect(result.performanceScore).toBeGreaterThanOrEqual(CWV_THRESHOLDS.performanceScore);
  });
  await test.step(`LCP meets the threshold (median across <run-count> runs: ${result.largestContentfulPaint}ms)`, () => {
    expect(result.largestContentfulPaint).toBeLessThan(CWV_THRESHOLDS.largestContentfulPaint);
  });
  // …CLS, INP, FCP, TBT — one step each
});
```

### What the helper guarantees

1. **Median-of-runs per metric.** Lighthouse on shared CI runners varies run to run, especially on LCP. Single-run thresholds flake; a median over several runs is stable. Median is computed **per metric independently** — not "the median run's report". The fastest run's LCP and the median run's CLS may both contribute.
2. **No parallelism within a test.** Runs execute serially. No `Promise.all` over runs.
3. **No `page.waitForTimeout()` between runs.** Lighthouse's own readiness signals sequence the runs. See `playwright-deterministic-awaiting` — `waitForTimeout` is forbidden everywhere.
4. **Artifact persistence on every run.** Per-run JSON saved to `<perf-results-dir>/{name}-{device}-run{idx}.json`; the median run's HTML report to `{name}-{device}.html`. The workflow uploads these as CI artifacts.
5. **Dedicated Chrome instance via chrome-launcher.** The helper launches one Chrome process per `runLighthouse()` call (reused across the runs to keep TLS / DNS state warm at the host level) and tears it down at the end. We do NOT share Playwright's browser — that path produces `net::ERR_ABORTED` with zero network requests captured because Playwright's CDP instrumentation and Lighthouse's navigation gatherer fight over request interception. The Lighthouse CLI's own launcher is what works.

### Variable naming

Lighthouse's API uses short metric names (`lcp`, `cls`, `inp`, `fcp`, `tbt`). In our helper return shape, **expand to full names**: `largestContentfulPaint`, `cumulativeLayoutShift`, `interactionToNextPaint`, `firstContentfulPaint`, `totalBlockingTime`. These names appear in `test.step()` titles and `expect.soft()` messages — they must be self-explanatory at first read.

Lighthouse-internal acronyms (`lcp` as a property on raw Lighthouse output, `LH` as the package import alias) stay verbatim — those are upstream APIs, not our code.

---

## Threshold management

### Hard rule: never loosen a threshold to make a test green

The thresholds in `<thresholds-file>` are **derived from Google's published Core Web Vitals standards**. They are not negotiable from a test author's seat.

When a route fails:

1. **Do not edit `<thresholds-file>`.** Even temporarily, even "just to unblock the PR".
2. **Follow `playwright-debugging-and-reporting` Phase 4b.** Assemble the evidence package (failure summary, measured values, top contributing audit per the Lighthouse `treemap-data`, `unused-css-rules`, `render-blocking-resources` audits), hand off for ticket creation, wait for the ticket URL.
3. **Mark the offending assertion** with the standard fixme pattern:
   ```ts
   // RED-by-design — tracked by ticket below.
   // Workflow: see .claude/skills/playwright-debugging-and-reporting/SKILL.md
   test.fixme(
     true,
     '<ticket-prefix>-XXX: home mobile LCP=<measured> (median), threshold <threshold>. Top contributor: <top-audit> (<savings>). See <ticket URL>.',
   );
   ```
4. **The active assertions stay active.** Only the metric that fails is `fixme`'d. A route that fails LCP but passes CLS keeps its CLS assertion live.

### Where threshold tightening IS allowed

After two consecutive clean nightlies (no regression, no fixme on any metric of a given route), the threshold for that route+metric **may be tightened** — never loosened. Document the tightening in the PR description with the observed values from the two clean runs.

### What's never a valid threshold change

| Change | Why it's wrong |
|---|---|
| Raise the LCP threshold above its current value | Decouples from Google's "Good" boundary, so the lab signal no longer means what the standard means. |
| Add a special-case threshold per locale | If a locale needs a different threshold, the locale has a real perf problem. File a ticket, fixme the failing locale, keep the threshold universal. |
| Switch `device: 'mobile'` to `device: 'desktop'` for a flaky route | Mobile is the KPI. Desktop coverage is regression, not a substitute. |
| Reduce the run count to save CI minutes | Single-run variance is what the median-of-runs exists to absorb. Saving CI time by introducing flake is a bad trade. |

---

## Emulation profiles

Both `mobile` and `desktop` are tested for every reserved AREA. Parameterised inside the spec — one canonical `@AREA-PERF-NNN` ID, two expansions.

```ts
for (const device of ['mobile', 'desktop'] as const) {
  test(`home page ${device} CWV thresholds`, {
    tag: ['@smoke', '@AREA-PERF-001'],
  }, async ({ page, locale }) => {
    // …
  });
}
```

### Tagging — do not use `@mobile`

`@mobile` is **reserved for the mobile-emulation Playwright project** (device emulation via Playwright's `devices` registry). Lighthouse mobile emulation is a separate mechanism with different throttling and viewport. Perf tests carry **only** the canonical `@AREA-PERF-NNN` tag plus a tier tag. Never `@mobile`.

### Mobile is the KPI; desktop is the regression net

The field-data CWV target is measured on mobile. Desktop tests catch the rare case where a desktop-only regression (e.g. a heavy hover preview, an unsplit desktop bundle) ships without affecting mobile. Both matter; only mobile is the KPI.

---

## What's forbidden

| Pattern | Why |
|---|---|
| `await page.waitForTimeout(N)` between Lighthouse runs | Forbidden everywhere — see `playwright-deterministic-awaiting`. Use Lighthouse's own readiness. |
| Mocking app requests with `page.route()` during a Lighthouse run | Mocks remove network cost; the measurement no longer reflects production. |
| Running Lighthouse alongside axe-core, screenshots, or video recording | Each adds CPU/I/O overhead that shifts LCP and TBT. Perf is its own project; do one thing per test. |
| Asserting `firstInputDelay` (FID) | Deprecated as a Core Web Vital. Use INP. |
| Asserting `timeToInteractive` (TTI) | Removed from the Lighthouse weighted score. |
| Parallelising the runs with `Promise.all` | Two simultaneous Lighthouse contexts skew each other's CPU measurements. Always serial. |
| Looser threshold "for a locale being added" | The threshold is global. File a ticket, fixme the locale, keep the threshold. |
| Running perf specs against `localhost` and reporting the numbers | Local CWV is unreliable (developer machine load, browser extensions, DevTools overhead add large variance). Authoritative measurements are staging-only. |
| Asserting a single metric's raw value across runs (e.g. `expect(run1.lcp)`) | Use the helper's median, not raw runs. Raw-run assertions are flake by design. |
| Modifying `<thresholds-file>` without referencing the upstream Google standard | The numbers are derived, not chosen. Provenance lives in code comments. |

---

## Triage workflow when a route fails

This is `playwright-debugging-and-reporting` Phase 4b, specialised for perf. Follow it strictly.

### Phase 1 — Read the artifact

Every failed perf spec leaves two relevant files in `<perf-results-dir>`:

- `{name}-{device}.html` — the median run's full Lighthouse HTML report. Open in a browser; it has the audit waterfall, treemap, and recommended fixes.
- `{name}-{device}-run{idx}.json` — one raw JSON per run. Use these to verify the median is stable (no run far from the others).

The HTML report's **Opportunities** section lists the top contributors to LCP / FCP / TBT in priority order. The **Diagnostics** section lists JS bundle size, image format issues, render-blocking resources, etc. Both contribute to the evidence package.

### Phase 2 — Classify the regression

| Pattern in the report | Likely cause | Where to look |
|---|---|---|
| Render-blocking CSS in `<head>` delaying first paint | Inlined critical CSS missing, full Tailwind bundle parsed | Critical-CSS inlining and the Tailwind bundle |
| LCP element is a hero image with no eager loading + no preload | Image lazy-loaded above the fold | Image `loading` attribute and preload |
| LCP element is text but FCP is slow | SSR is slow — backend TTFB or BFF waterfall | Parallel SSR fallbacks (step 4 of the diagnosis) |
| TBT is high | Large JS bundle blocking main thread | Check `unused-javascript` audit |
| CLS is high | Late-loading fonts, ads, or images without dimensions | Image, font, and ad sizing |
| Run-to-run variance is high | Lighthouse / network instability — flake, not regression | Re-run; if persistent, increase the run count |

"High", "slow" and "late" here mean past the threshold in `<thresholds-file>`, not a number written in this skill.

### Phase 3 — Evidence package for ticket creation

Hand off:

- **Failure summary** — one paragraph: which AREA/device, measured median, threshold, route, branch, environment (`staging`).
- **Lighthouse Opportunities top 3** — copy-paste from the HTML report's "Opportunities" section verbatim. Each line includes the metric impact (e.g. *"Eliminate render-blocking resources — Potential savings of <savings>"*).
- **Audit excerpt** — the specific audit JSON for the top contributor (e.g. `render-blocking-resources.details.items[]`). Trim to the 5–10 most impactful entries.
- **Code reference** — if the diagnosis points at a known anti-pattern in the codebase, cite the file:line. *Example:* `<layout-file>:<line> — global stylesheet imported without critical-CSS split`. If you can't locate code, say "not yet located" — don't speculate.
- **Run-to-run table** — for each run, list LCP/CLS/INP/FCP/TBT. Highlights variance.

### Phase 4 — Fixme

After ticket creation returns a URL:

```ts
// RED-by-design — tracked by ticket below.
// Workflow: see .claude/skills/playwright-debugging-and-reporting/SKILL.md
test.fixme(
  true,
  '<ticket-prefix>-XXX: <page-path> mobile LCP=<measured> (median; runs <run-values>), threshold <threshold>. Top contributor: <top-audit> (<savings>). See <ticket URL>.',
);
```

Only the specific failing metric is fixme'd. The active CLS/INP/etc assertions stay live for that route.

---

## Reference implementations

| Pattern | Canonical location |
|---|---|
| `runLighthouse` helper (median-of-runs, persistence) | `<perf-helper-file>` |
| Threshold constants (derived from Google CWV) | `<thresholds-file>` |
| Per-AREA route registry | `<routes-file>` |
| Reference perf spec (home page) | under `<perf-specs-dir>/<area>/` |
| Playwright `perf` project config | `<e2e-dir>/playwright.config.ts` |
| CI workflow (nightly + manual dispatch) | `<perf-ci-workflow>` |
| Implementation plan | `<perf-plan-doc>` |

These files are authoritative. When the skill paraphrases reality, the code wins.

---

## Checklist before merging a perf test

- [ ] Spec is under `<perf-specs-dir>`.
- [ ] Imports `test`/`expect` from `<fixtures-module>` — never from `@playwright/test`.
- [ ] All Lighthouse calls go through `runLighthouse` in `<perf-helper-file>` — no inline `lighthouse()` invocations.
- [ ] Thresholds read from `<thresholds-file>` — no inline numeric literals in `expect()`.
- [ ] Both `mobile` and `desktop` expansions are parameterised inside one `for (const device of ['mobile', 'desktop'])` loop sharing one canonical `@AREA-PERF-NNN` ID.
- [ ] No `@mobile` tag. The `@mobile` tag is reserved for the mobile-emulation project — perf uses Lighthouse's own emulation.
- [ ] Every assertion in its own `test.step()` with the measured value interpolated into the title (e.g. `LCP meets the threshold (median across <run-count> runs: <measured>ms)`).
- [ ] No `page.waitForTimeout()` anywhere.
- [ ] No `page.route()` mocking during the Lighthouse run.
- [ ] No screenshots, video recording, or axe-core scans interleaved with Lighthouse.
- [ ] No assertion on `firstInputDelay` or `timeToInteractive`.
- [ ] The run count is at least the minimum set in `<perf-helper-file>` in `runLighthouse(...)` options.
- [ ] Spec runs against staging — `isStagingRun` check guards local invocations from polluting the metric history.
- [ ] If a route currently fails: ticket filed via ticket creation, fixme uses the standard preamble + ticket URL.
- [ ] No edits to `<thresholds-file>` — if the threshold is "too tight", file a ticket, not a PR.
- [ ] One tier tag (`@smoke` for the flagship gates; `@regression` for secondary surfaces).
- [ ] Canonical `@AREA-PERF-NNN` ID from the project's test registry.

---

## Definition of done

The promise of this gate is that no route ships without a passing CWV check. The operational test of that promise is:

1. Every deployed locale has a green home-page perf test (`@AREA-PERF-001`, mobile + desktop) on the latest nightly.
2. Every key page type has a passing perf test (`@AREA-PERF-NNN`, mobile + desktop) on the latest nightly.
3. Every fixme'd assertion has a ticket and an owner.
4. The threshold table in `<thresholds-file>` matches Google's published "Good" boundaries — and the in-repo provenance comment cites the upstream URL.

If any of those four conditions is false, the perf gate is not in place, whatever the test matrix shows. The gate exists so that anyone can check the claim against the upstream standard.
