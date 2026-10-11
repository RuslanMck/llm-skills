---
name: ci-faild-test-debug
description: "Investigate one or more failed CI e2e jobs end-to-end: pull logs + pre-downloaded artifacts, separate real failures from expected-fail/skips, REPRODUCE locally against staging and local before concluding, prove the root cause with evidence, and report it in a fixed format (what failed, how the user sees it, affected area, coverage, whether it needs its own test, the PR that introduced an app bug, or — for a test bug — what was wrong and how to make the oracle stable without hardcoding the root cause). Use when given CI job/run URLs (github.com/.../actions/... or the CI evidence-server link) and asked why tests failed."
---

# CI failed-test debug

## Placeholders

- `<company-name>/<project-name>` — the GitHub owner and repository the CI runs belong to
- `<ci-evidence-host>` — the host of the server that stores downloaded CI report artifacts
- `<evidence-path>` — the path prefix on that server under which reports are stored
- `<e2e-target-env-var>` — the environment variable your project uses to set the base URL / target environment for e2e tests
- `<e2e-spec-target>` — the make target for running a single e2e spec (check your `Makefile`)
- `<authenticated-project-name>` — the Playwright project name that uses authenticated storage state

One entry point for investigating failed CI e2e jobs. This skill **investigates and proposes — it
does not act**: it does not edit tests, file tickets, commit, or touch app code. It produces a
reasoned, evidence-backed report and, for a test issue, a *proposed* fix for a human to act on.

The goal is a **proven** root cause, not a plausible one: every conclusion is backed by a local
reproduction and by evidence a human can re-check. Never hand back a guess.

**Every distinct failed test is its own investigation.** When a run (or several runs) has multiple
separate failures, do not collapse them into one verdict or assume a shared cause — reproduce,
prove, classify, and report **each one independently**, with its own result section. Different
failures in the same job routinely have different root causes (one a real app bug, another a flake,
another a transient drift). Identical failures of the *same* test across locales/shards may be
grouped into one section; genuinely different tests may not.

## Inputs this skill expects

The user pastes one or more of:
- **GitHub job/run URLs** — `github.com/<company-name>/<project-name>/actions/runs/<runId>/job/<jobId>`.
- **Evidence-server URLs** — `https://<ci-evidence-host>/<evidence-path>/<runId>/<report-name>/...`

**Artifacts are already downloaded.** The evidence server at
`https://<ci-evidence-host>/<evidence-path>/<runId>/<report-name>/` stores every
failed job's Playwright report (index, traces, screenshots, `data/*.md` error-contexts, network
timelines). Fetch from there instead of `gh run download` — it is faster and avoids re-downloading.
`gh run download` is only a fallback if the evidence server is unreachable.

---

## Step 1 — Resolve the target and confirm the code under test

1. For each run: `gh run view <runId> --repo <company-name>/<project-name> --json headSha,headBranch,event,status,conclusion,jobs`.
2. Get the failing job's **name** and **conclusion**; map the `<jobId>` to it.
3. **Confirm the failing code is actually in this run.** Squash-merges rewrite SHAs, and
   `staging`/preview runs lag `master` behind a promote. Check the file content *at the run's
   headSha* (`git show <sha>:<path>`), not just "I merged a fix." A fix on `master` is not on
   `staging` until promoted — a still-red staging run may simply predate the fix.

## Step 2 — Collect evidence from ALL sources

4. **Logs** — `gh api repos/<company-name>/<project-name>/actions/jobs/<jobId>/logs` (works mid-run;
   `gh run view --log` is empty until the whole run finishes). Strip ANSI: `sed -E 's/\x1b\[[0-9]*m//g'`.
5. **Separate real failures from noise — the reporter's final summary is authoritative**, not the
   inline ✗ marks in the body. It prints three buckets:
   - `N failed:` — the real, leg-failing failures. **These are the target.**
   - `M expected-fail (test.fail, known-issue — does not fail the leg):` — tracked defects; NOT the
     cause of the red. Note them, do not chase them.
   - the skip list — feature-flagged / data-gap / env skips; also not failures.
   A single ✗ in the body is often an expected-fail or a soft-assert; only the summary tells you
   which actually failed the job.
6. **Retries decide the diagnosis.** Failed-then-passed on retry = **flake**; failed on every
   attempt = **deterministic**. Read the `[n/total]` attempt lines.
7. **Artifacts from the evidence server** — open the report at the evidence URL and read, for each real
   failure: `error-context.md` (the failing values + accessibility snapshot), the **network
   timelines** (`[Timeline] → / ← status URL`), screenshots, and the trace. The log line is the
   symptom; the artifact carries the state.

## Step 3 — REPRODUCE before concluding (mandatory)

Never classify from the log alone. Reproduce the specific failing test:

8. **Against staging** (the env CI ran against):
   ```bash
   cd tests/e2e && <e2e-target-env-var>=staging \
     npx playwright test <spec> --project=<project> --workers=1 --grep "<test title fragment>"
   ```
   Secrets and passwords live in `tests/e2e/.env`; `<e2e-target-env-var>=staging` overrides the
   base URL. (If no `make` target sets `<e2e-target-env-var>`, run `npx` directly — still
   `cd tests/e2e` first so the config/node_modules resolve.)
9. **Against local** too when the surface exists locally (`make <e2e-spec-target> SPEC=...`, local Docker
   stack) — a bug that reproduces on staging but not local, or vice versa, is itself evidence
   (env-specific config, missing local backend data store, egress, etc.).
10. **Reproduce the way the TEST runs it, through the Playwright runner — not a simplified probe.**
    A standalone `curl` or a tiny script can pass while the real test fails, because the test
    inherits project context the probe doesn't (fixtures, `use.storageState`, `extraHTTPHeaders`,
    ordering). Example: an "anonymous" `request.newContext()` inside an `<authenticated-project-name>` project
    inherits the project `storageState`, so it is silently authenticated — a curl never sees that.
    If a probe disagrees with the test, trust the runner and find what context differs.
11. **Re-check the CURRENT live state — staging is shared and changes underneath you.** A CI failure
    can be point-in-time: data or content rolled out in stages, an in-flight deploy, a promote.
    If a re-run now passes, the failure was transient drift, not a standing bug — say so, with the
    before/after.

## Step 4 — Prove the root cause

12. Trace **both sides** of any comparison to their source (e.g. a rendered value ← the data API;
    visible text ← an SSR render vs a client-side fetch). A mismatch only
    means something once you know where each side comes from.
13. Use a **known-good baseline** — a prior passing run of the *same* test. "This exact test passed
    at run X and fails at run Y, and only <data/app> changed between them" is the strongest evidence
    available. Pull the older run's log and diff the relevant values.
14. If **not sure, double-check** — another reproduction, another locale, the live SSR HTML, the
    trace. Do not report a cause you could not reproduce or could not source. Uncertainty stated
    honestly beats a confident wrong answer.
15. **Classify** into exactly one:
    - **App/data bug** — the app or its data is wrong; the test correctly caught it.
    - **Transient drift** — was real, now resolved by a later deploy or data change.
    - **Test bug** — the app is right; the test or its oracle is wrong.
    - **Environment/flake** — backend egress 503, cold-staging latency, the edge firewall, cache — not the
      app, not the test's logic.

---

## Result format — report, do not act

This skill is **investigation and proposals only**. It does not fix tests, file tickets, commit, or
change app code — it produces a reasoned, evidence-backed report and, for a test issue, a *proposed*
fix.

**One result section per distinct failed test.** If there are multiple separate failures, produce a
separate, complete result for each — never a single merged verdict. (Only identical failures of the
same test across locales/shards are grouped.) Each section is led by its own classification
(app/data bug · transient drift · test bug · environment/flake), then answers the branch that
applies below.

### If it is an APP issue (app/data bug, or transient drift)

- **What failed** — the test, the assertion, and the concrete failing values (not just the rule).
- **How the end user sees it** — the customer-visible symptom in plain words, or "invisible /
  internal-only" if it is.
- **What part of the application is affected** — the surface/subsystem and the data source(s).
- **Does our test cover this case** — did an existing test catch it (which one), or did it slip
  through; is the coverage at the right layer.
- **Does this case deserve its own test** — yes/no and why; if yes, sketch the missing test.
- **What PR introduced the issue** — find it (git log / blame around the changed behaviour, the
  run's baseline diff, `gh pr list --search`); name the PR and author-team. For transient drift,
  name the rollout/deploy that caused it instead.

### If it is a TEST issue (test bug, or an environment/flake the test should tolerate)

- **What exactly was incorrect** in the test or its data oracle.
- **Why we plausibly introduced it at creation time** — the trap that looked correct then.
- **How to fix it** — the proposed change (do not apply it here; this is a proposal).
- **How to make the test / data oracle more stable and scalable, without losing test coverage and
  without hardcoding the failure's root cause** — e.g. derive the expected value from an independent
  source (computed / semantic-state / app-i18n), wait on the app's own settled signal instead of a
  fixed timeout, reuse an existing ready/settle helper, and make the failure **message** name the
  specific diverging facts. Never pin the exact live values or special-case the one thing that broke
  — the oracle must still catch the *next* regression.

Back every claim with evidence: the failing values, the source of each side, the local reproduction
result (staging and/or local), the baseline diff, and the current live state.

---

## Related (for context only — this skill takes no actions)

- `e2e-review` — the review canon and the failure-message rule, if the user later acts on a proposal.
- `playwright-core` / `playwright-test-review` — the oracle rules and finding taxonomy.
- Repo `tests/e2e/CLAUDE.md` — app-immutability rule; the layout/config this skill reads.
