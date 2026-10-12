# Default target map (a proposal, not a decision)

The orchestrator starts its plan from this table, adjusts it to what the inventory shows, and
shows the result to the user for approval. Names are suggestions.

| Target | Disposition | Sources | Scope |
|---|---|---|---|
| `test-review` | merge | `e2e-review`, `playwright-test-review` | Reviewing test code: naming, single responsibility, DRY, formatting, comments, assertion quality, locator and wait reliability, skip/fixme reasons, failure-message quality. Keeps the existing report format. Does not teach how to write tests. |
| `playwright-test-design` | merge | `playwright-core`, `playwright-ui`, `playwright-api` | Writing tests: arrange-act-assert, page objects and fixtures, isolation, test data setup, `test.step`, titles, skip/fixme/fail, UI and API specifics. Detail in `references/ui.md` and `references/api.md`. |
| `playwright-locators` | rewrite | `playwright-locators` | Locator strategy, semantic first (rubric 5). Adding test IDs to app code when no semantic handle exists. Framework-agnostic (no Astro). |
| `playwright-waiting` | light-pass | `playwright-deterministic-awaiting` | Waiting for the right signal: web-first assertions, response waits, app-state signals; what is forbidden. |
| `test-failure-investigation` | merge | `ci-faild-test-debug`, `playwright-debugging-and-reporting` | Reproduce, prove, classify (app / test / environment / drift), and report a failing test, from CI or local. |
| `api-contract-testing` | rewrite | `playwright-zod-strict-schema-envelope` | Validating response bodies against schemas; strict vs open schemas; what to do when the backend adds a field. Zod as an example. |
| `multi-locale-testing` | rewrite | `playwright-locale-validation` | Only for apps with more than one locale: locale-agnostic paths, URLs, data and assertions. |
| `web-performance-testing` | rewrite | `playwright-performance` | Core Web Vitals in lab tests: metrics, thresholds, emulation, median of runs, never loosening a threshold to go green. |
| `third-party-iframes` | rewrite | `playwright-adyen` | Testing embedded third-party widgets (payments, captchas, maps) in iframes. Adyen as an example. |
| `test-failure-artifacts` | rewrite | `playwright-extensive-logging` | What to log and attach on failure (network, console, timings) so a failure is diagnosable from CI. Not one project's fixture code. |
| `playwright-cli` | keep | `playwright-cli` | Already generic. No subagent. |
| `simple-words` | keep | `simple-words` | Already generic. No subagent. |
| — | move | `commit-push`, `my-linear-tickets`, `knowledge-base-doc-authoring`, `plan-to-checklist` | Personal workflow, not QA. Move to `personal/` (or drop, if the user says so). |
