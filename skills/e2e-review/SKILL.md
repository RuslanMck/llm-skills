---
name: e2e-review
description: "Review Playwright e2e test files against the full canon (core rules, locale-agnosticism, locators, POM/fixtures/specs/support/test-data canons). Use when asked to review, audit, or check an e2e spec, POM, fixture, or support file — e.g. \"/e2e-review path/to/foo.spec.ts\", \"review this spec\", \"audit the <resource> POM\"."
---

# E2E Review — orchestrator

One entry point for reviewing anything under `<e2e-dir>/`. This skill **owns no rules**. It
resolves the target, loads the canon in the right order, and hands off to
`playwright-test-review`'s procedure. If a rule seems to live here, it is in the wrong place —
put it in the owning skill or README.

## Placeholders

Map each placeholder to your own repo before use. Each one stands for a structural element;
the rules hold for any repo that has the same role.

- `<project-name>` — the repo this canon belongs to.
- `<e2e-dir>` — the root of the Playwright e2e suite. Its sub-folders (`specs/`, `pages/`,
  `components/`, `fixtures/`, `support/`, `test-data/`, `services/`, `schemas/`, `tools/`) are the
  layout this canon expects; rename them here if your suite uses other names.
- `<app-dir>` — the front-end application root, the folder that holds `src/`.
- `<backend-dir>` — the server-side application root.
- `<i18n-dir>` — the folder of per-locale JSON files the app renders its copy from.
- `<contracts-dir>` — the shared folder of API contract schemas.
- `<ci-scripts-dir>` — the folder of CI guard scripts.
- `<ticket-prefix>` — the issue-tracker key prefix used in TODO markers and skip reasons.
- `<quarantine-tag>` — the test tag that parks a test pending a ticket.
- `<quarantine-register>` — the document that lists each quarantined test and its ticket.
- `<tags-precommit-script>`, `<tags-audit-script>` — the QA tag-check and tag-rewrite tools.
- `<fast-gate-job>` — the fast CI job that runs the guards on every change.
- `<area>`, `<name>`, `<feature-flag>`, `<contract>` — placeholders for a feature folder, a file
  name, a feature flag and a contract file, used in examples.
- `<i18n-helper>` — the test utility that looks up i18n strings by locale and key.
- `<i18n-helper-file>` — the source file of `<i18n-helper>`, under `<e2e-dir>/support/util/`.
- `<list-mismatch-helper>` — the assertion utility that computes and formats a multiset diff between two value lists.

---

## Step 0 — Resolve the target

The argument is a spec/POM/fixture path, a bare filename, or a description.

- **A path** (`<e2e-dir>/specs/ui/<area>/<name>.spec.ts`) → review that file.
- **A bare filename** (`<name>.spec.ts`) → locate it:
  `find <e2e-dir> -name "<filename>"`. Two hits → ask which.
- **Nothing, or "my changes" / "this branch"** → the full working scope, the UNION of all four
  (a new spec that is only staged, or still untracked, MUST be reviewed):
  - committed vs master — `git diff --name-only origin/master...HEAD -- <e2e-dir>/`
  - staged — `git diff --name-only --cached -- <e2e-dir>/`
  - unstaged — `git diff --name-only -- <e2e-dir>/`
  - untracked — `git ls-files --others --exclude-standard -- <e2e-dir>/`

  The mandatory pre-commit review (`<e2e-dir>/CLAUDE.md` directive 5) runs here, so leaving out
  the staged and untracked sets would let an unreviewed file through against an empty or stale scope.

State the resolved file list in one line before reviewing. Never review a file you did not read
in full — a review from a diff hunk alone misses the POM/fixture it depends on.

Also read what the target **depends on**: the POMs, fixtures, support helpers, and test-data it
imports. Most real findings (an inline locator that duplicates an existing getter, a hand-typed
string that exists in i18n, a re-implemented mock) are only visible against those files. This is
the reuse-first rule and it cannot be checked from the spec alone.

## Step 1 — Load the canon

Load in this order. Later sources are more specific and win on conflict.

**Skills** — invoke via the Skill tool (skip any that this environment does not list):

1. `playwright-core` — shared rules: layout, tagging, `test.step`, titles, skip-vs-fixme, soft
   assertions, and the inlined fixtures / specs / POM / support / test-data canons.
2. `playwright-locale-validation` — locale-agnostic paths, URLs, fixtures, assertions.
3. `playwright-locators` — `data-testid` strategy and naming, for anything locator-shaped.
4. `playwright-test-review` — the review procedure itself and the finding taxonomy.
5. If present in this repo, also: `playwright-ui` (browser specs), `playwright-api` (HTTP specs),
   `playwright-deterministic-awaiting` (waits/hydration),
   `playwright-adyen` (payment specs). Load the ones the target actually touches.

**READMEs — authoritative when present.** In a `<project-name>` repo these are the canon; the
skills only mirror them. Read the ones covering the directories the target touches:

| Target touches | Read |
|---|---|
| any file under `<e2e-dir>/` | `<e2e-dir>/README.md` |
| `specs/**` | `<e2e-dir>/specs/README.md` |
| `pages/**`, `components/**` | `<e2e-dir>/pages/README.md` |
| `fixtures/**` | `<e2e-dir>/fixtures/README.md` |
| `support/**` | `<e2e-dir>/support/README.md` |
| `test-data/**` | `<e2e-dir>/test-data/README.md` |
| `schemas/**`, `services/**`, `tools/**` | that directory's `README.md` |

Glob `<e2e-dir>/**/README.md` rather than trusting this table — a new canon may have landed.
Outside a `<project-name>` repo none of these exist; the skills' inlined canons are then the only source,
and findings that depend on repo-specific paths or guards do not apply.

## Step 2 — Run the machine guards first

Findings a guard already prints are free and non-negotiable. From the repo root, for the
directories in scope:

```bash
node <ci-scripts-dir>/check-specs-canon.mjs
node <ci-scripts-dir>/check-pom-canon.mjs
node <ci-scripts-dir>/check-fixture-canon.mjs
node <ci-scripts-dir>/check-support-canon.mjs
node <ci-scripts-dir>/check-test-data-canon.mjs
node <ci-scripts-dir>/check-schemas-canon.mjs      # when schemas/** is in scope
node <ci-scripts-dir>/check-services-canon.mjs     # when services/** is in scope (BLOCKING by default)
node <ci-scripts-dir>/check-tools-canon.mjs        # when tools/** is in scope
node <ci-scripts-dir>/check-root-canon.mjs
node <e2e-dir>/tools/<tags-precommit-script>.mjs --all   # tier/surface/ID tags
```

Skip a guard that does not exist here. Every hard finding a guard prints is a Critical review
finding — do not re-derive it by eye. **Never run `<tags-audit-script> --fix`** (destructive: it
rewrites specs wholesale and injects duplicate IDs).

**`<tags-precommit-script>.mjs` needs `--all`.** A bare invocation scans the *staged* file list, which
in a review is usually empty, so it exits 0 having checked nothing — a vacuous pass. `--all`
scans the whole suite; or pass the resolved target files explicitly.

Report guard failures separately from your own findings, so it is clear which are already
enforced in `<fast-gate-job>` and which need a human.

## Step 3 — Review

Follow `playwright-test-review` Steps 1–8 in order and use its severity scale
(Critical / Architectural debt / Optimization). For the **output**, use §"Report format" below —
it supersedes `playwright-test-review`'s format for anything this skill produces.

Two rules from that skill matter most and are worth restating because they are what makes a review
worth reading:

- **Quote `file:line` and the offending line.** "Looks fine" is not a finding, and neither is a
  finding with no location.
- **Report, never silently edit.** This skill produces a findings report. Apply fixes only when
  the human asks, and then one at a time with the finding quoted.

## Step 4 — Judgment the guards cannot reach

After the mechanical passes, spend the remaining attention where no gate looks:

- **Names that do not survive being read on their own.** Apply `playwright-test-review`
  Step 3b ("Naming findings") to **every name the diff introduces or renames** — variables,
  constants, parameters, callback params, functions, helpers, methods, types, fields — across
  specs, support, pages, components, fixtures, services, schemas. **There is no denylist and no
  grep here**: a token list only ever catches the bad words somebody already thought of, and the
  names that slip through are the ones nobody listed. Instead take each name with the code
  covered — no file, no type, no surrounding lines — and write one line saying what it holds or
  what it does. If you need the body, the type signature, or a usage to write that line, the name
  is the finding; report it with `file:line`, the name, and the plain-language line the name
  should have supported. Every hit is Architectural debt at minimum, Critical when the name says
  one thing and holds another. **This bullet is first on purpose, and when you wrote the code
  under review it runs BEFORE the correctness hunt** — it is the check most often skipped when the
  mechanics pass, "reads fine to me" is precisely the author bias it exists to catch, and the
  omission is visible to every later reader.
- **Reuse-first violations** — an inline locator/mock/factory/string that duplicates something
  `pages/`/`support/`/`test-data/`/`<i18n-dir>` already owns. The #1 rule in the specs canon
  and the most common real finding.
- **Hardcoded UI strings (the i18n oracle).** Every assertion on user-facing *wording* must take its
  expected value either from **semantic state** (a `data-state`/`data-*` hook via a POM getter —
  prefer this, it is locale-proof) or from **`<i18n-helper>(locale, key)`** in
  `<e2e-dir>/support/util/<i18n-helper-file>.ts`, parameterised by the `locale` **fixture**. A hand-typed
  literal — `toHaveText('Awaiting your files')`, `getByText('Continue')`, a local `const LABELS = {…}`,
  an English regex over copy — is a finding even when it currently passes: it is locale-bound and
  asserts nothing about translation wiring. Also flag `<i18n-helper>` called with a hardcoded locale, and
  verify the key actually exists in `<i18n-dir>/<locale>.json` **and** is the key the component
  renders (`t(locale, '<key>')`). Not findings: non-user-facing literals (testids, slugs,
  `data-state` values, API enums), and copy genuinely absent from the app's i18n — provided it is
  extracted once into `support/`/`test-data/` with a reason, not inlined. Translation *quality* is
  out of scope; we test wiring.
- **Uncontracted endpoints — "what validates this response body?"** For every endpoint an API spec
  exercises, open the service method behind it and answer that question. A method on
  `parseResponseLoose` validates the ERROR envelope and **nothing else**, so a spec asserting a
  body field against it has pinned whatever the endpoint returned the day it was written; a
  renamed or reshaped field then fails downstream, or silently passes. **Critical** when a spec
  asserts body fields with no schema behind them; **Architectural debt** when the loose parse
  carries no `TODO(<ticket-prefix>-####)` naming what will model it. Rule owner: `services/README.md`
  rule 5a — "`parseResponseLoose` is a debt marker, not an exemption" — reported by
  `check-services-canon.mjs`, which is BLOCKING by default (setting its blocking switch to `0`
  downgrades it), so run it (Step 2) and read its rule-5a block rather than eyeballing.
  Also check `<contracts-dir>/` **before** accepting a test-local schema as correct: a
  canonical contract may already exist under a name that does not match the endpoint path
  (`<contract>.zod.ts` covers `GET /api/<version>/<resource>/{id}`), and a local
  duplicate of a contracted endpoint is worse than no schema — both look authoritative.
- **Assertion oracles** — a computed value read back from the app or a service and then asserted
  against the app is a tautology: the test cannot fail for the bug it exists to catch. Critical.
- **Journey vs area placement** — does this file mock (→ area) or walk the real flow (→ journey)?
  A journey that stubs anything has faked the seam it exists to prove.
- **Does it go red for the right reason?** For each assertion, name the defect it would catch. An
  assertion with no answer is decoration.
- **Failure-message quality — the message a reader lands on must state the FACTS, not the rule.**
  When an assertion fails, its message (and the `test.step` title it surfaces under) is the whole
  signal a human gets in the CI summary and `error-context.md`. A message that only restates the
  invariant — `"…must list the same values, in the same order"`, `expected true`, `toEqual failed`
  — is a finding: it is identical on every failure of that assertion, so the reader must reopen the
  trace and re-derive the diff by eye. Flag any assertion whose message does not name the specific
  values/facts that diverged. Point at §"Failure messages" below for the canon and the fix.
- **Comment locality (≤5 lines per block).** A single comment block that runs past ~5 lines belongs
  in the folder's README, not wedged into the code file. Flag it and point at §"Comment locality"
  below for the exact remedy.

---

## Report format

Plain markdown. No emoji, no preamble, no summary paragraph, no "great work overall". The list is
the report.

### Sections

Fixed order, and **omit any section that has no findings** — never print an empty heading — with
the single exception of `Naming`, which is **always printed** (see below):

```
Critical
Architectural debt
Optimization
Naming
```

**`Naming` is a mandatory, always-present section.** It carries every naming finding (from Step 4's
"Names that do not survive being read on their own" / Step 3b), regardless of the finding's severity,
so the reader can see the naming status of the diff at a glance instead of hunting for it scattered
across the severity buckets. It is the one section printed even when empty: with no naming findings,
print exactly

```
Naming
- none — every name the diff introduces or renames read clean on its own.
```

so it is explicit that the naming pass ran and came back clean (a silent absence is indistinguishable
from a skipped pass — the failure mode this section exists to prevent). Inside the section each finding
carries its severity inline as the first word after the dash (`Critical` / `Architectural`), exactly as
a themed section does. A naming finding lives **only** in `Naming`, never also under its severity
section, and is counted **only** in the `Naming` tally (never double-counted in Critical/Architectural).

**Other themed sections are allowed when they earn it.** When **≥3 non-naming findings share one
theme**, give that theme its own section instead of scattering them, placed after `Naming`. Useful
themes: `i18n`, `a11y`, `Determinism`, `Performance`, `Locale`, `Reuse`. Inside a themed section each
finding carries its severity inline as the first word after the dash. A finding lives in **exactly
one** section — never list it under both its severity and its theme.

### A finding

```
- <path>:<line> — <one sentence, lowercase, saying what is wrong>
<the offending code, verbatim, indented — no fence needed>
  - <the evidence: the mechanism that proves it, naming symbol (path:line-range) and quoting the
    code that does it>. <Why that makes the finding true.> <Canon citation: the guard step, README
    section, or skill § that owns the rule, quoted.>
  <The remedy, as an imperative: what to delete, extract, or reframe it against — naming the
  concrete helper, home, or symbol.>
```

Rules:

- **The diagnosis is one sentence** and states the defect, not the category. "the assertion is
  structurally incapable of failing" — not "vacuous assertion".
- **Quote the code verbatim.** A finding with no quoted line is not a finding.
- **The evidence sub-bullet is what makes the report worth reading.** Do not assert that something
  is broken — show the mechanism. Trace to the function/POM/fixture that causes it, cite its
  `file:line`, and quote the operative code. A finding whose evidence you cannot trace this way is
  a suspicion; either verify it or drop it.
- **Cite the canon** by its owner (`Step 2b: "…"`, `specs/README.md §"Assertion oracles"`,
  `playwright-core §skip-vs-fixme`), quoted so the reader can check it without opening anything.
- **End with the remedy**, and give the alternative when there is a choice ("Delete it, or reframe
  it against an independent expected-value list in `<test-data-dir>`").
- **Note redundancy** where a finding overlaps existing coverage — "line 162 of the mirror test
  already makes the real version of this check" is often the strongest argument for a delete.
- **Group by file, ordered by how much the reader should care** — several findings in one file each
  get their own bullet.
- **`Optimization` may hold a keep-this note.** Naming what is already correct and worth copying as
  the model for sibling specs is a legitimate entry — it tells the reader what not to "fix".

### Final line

Exactly one line, always last. Use the short form `Architectural` in the tally. **The `Naming` count is
always present, even when zero** (`0 Naming`), so the tally itself confirms the naming pass ran; it counts
the findings in the `Naming` section and nothing else (they are not also in the Critical/Architectural
counts). Add a parenthetical when findings implicate files beyond those reviewed:

```
6 Critical, 8 Architectural, 1 Optimization, 2 Naming across 1 file (2 Critical findings also implicate support/<area>/<grouping>.ts and support/util/<helper>.ts).
```

A clean naming pass still shows in the tally: `1 Critical, 4 Architectural, 3 Optimization, 0 Naming across 5 files.`

### Worked example — match this shape

```
Critical

- <e2e-dir>/specs/ui/<area>/<name>.spec.ts:87 — the assertion is structurally incapable of failing.
  expect(
    emptyGroups,
    `Groups with zero items: ${emptyGroups.join(', ')}`,
  ).toHaveLength(0);
  - groupByField (support/<area>/grouping.ts:31-37) creates a group key only at the moment it pushes an item into it — if (!groups.has(field)) groups.set(field, []); groups.get(field)!.push(item).
    A zero-length group cannot exist in its output, so @<area>-UI-024 has never been able to fail. Step 2b: "Vacuous / self-comparing assertion — an expect whose two operands derive from the same source can never fail … Critical."
  It is also redundant: line 61 of the mirror test already makes the real version of this check, per field, against the same map. Delete it, or reframe it against an independent list of expected groups (<e2e-dir>/test-data/<area>-categories.ts).

Architectural debt

- <name>.spec.ts:76 — one hardcoded size for every variant, and it now contradicts the centralised scenario data.
  new URLSearchParams({ variant: variant, size: 'large' }),
  - <e2e-dir>/test-data/<area>-scenarios.ts now pins per-variant params — variant A on large, variant B on small. This helper forces large on variant B too, so if that combination is unavailable the group may not render and the test fails for the wrong reason.
  Read the scenario data instead of re-deciding the size here.

Optimization

- <name>.spec.ts:36-62 — the header, the centralised data constants, the locale-fixture usage, and the two deletion-rationale comments (348-352, 496-499) are all correct and worth keeping as the model for the sibling specs. No hardcoded locale anywhere; the locale fixture drives every comparison.

Naming

- Architectural — support/<area>/grouping.ts:31 — `groups` says its shape (a map) but not its subject; read on its own it could hold anything.
  const groups = new Map<string, Item[]>();
  - From the name alone a reader cannot say what these are grouped BY or what they hold — you have to read the body to learn it is records keyed by field. Step 3b "Names that do not survive being read on their own": "its shape or type — that it is a list / map / object / value, but not of what".
  Rename to the subject: `recordsByField`.

6 Critical, 8 Architectural, 1 Optimization, 1 Naming across 1 file (2 Critical findings also implicate support/<area>/grouping.ts and support/util/<helper>.ts).
```

(When the naming pass finds nothing, the section is still printed — `Naming` then `- none — every name the diff introduces or renames read clean on its own.` — and the tally still carries `0 Naming`.)

---

## Failure messages state the facts, not the rule

When an assertion fails, its message — and the `test.step` title it surfaces under — is the WHOLE
signal a human gets in the CI summary, the reporter's failed-list, and `error-context.md`, usually
without opening the trace. A message that only restates the invariant is a finding: it reads the
same on every failure of that assertion, so it tells the reader a contract exists but not which
data broke it, forcing them to reopen the trace and re-derive the diff by hand.

**The canon — a good failure message:**

- **States the actual-vs-expected as concrete VALUES, not just the invariant.** Name the items that
  diverged, and the direction (present-but-unexpected ≠ expected-but-missing ≠ same-set-wrong-order).
  The message should be the conclusion, not the raw material to re-derive it.
- **Is specific to THIS failure instance.** If two different failures of the same assertion produce
  an identical string, the string is under-informative.
- **Reads in DOMAIN language, not the test's internals.** The reader may be a PM or a content
  editor. `"shown on the page but missing from the '<info-block>' block: <value>"` beats
  `"the record must list the same values as the source"`; `expected true` / `toEqual failed`
  with no context is the worst case.
- **Points at the cause, not the mechanism.** Where to look ("missing from the <info-block> block"),
  not what the matcher did ("toEqual failed").
- **Stays honest to the assertion.** The message may be richer than the check but must never claim
  more or less than what actually failed — the matcher is unchanged; only the narration improves.
- **Lands where the reader lands.** The reporter surfaces the **assertion message** (the 2nd arg to
  `expect`) and the failing `test.step` title. Putting the computed diff only in a `console.log`, or
  only in a step title while the `expect` message stays generic, does not count — compute it and put
  it in the message. When a helper owns the `expect` (e.g. `support/domain/**` assertion helpers),
  the message duty lives there; a spec that passes it a bare value cannot add context after the fact.

**Before → after (the shape to require):**

```
// ❌ restates the rule — identical on every failure, forces a trace dig
expect.soft(documented, `"${attr}"'s record must list the same values, in the same order`).toEqual(offered);

// ✅ names the specific values and the direction, in domain words.
// Diff as a MULTISET (count occurrences), NOT with `includes` — otherwise a value
// repeated on one side but not the other (offered=[A,B,B], documented=[A,B]) makes
// both filters empty and is mislabelled "same values, wrong order". Prefer the
// shipped helper (`<list-mismatch-helper>` in <e2e-dir>/support/util/); the inline
// multiset diff below is what it does.
const onlyIn = (a, b) => { const rest = [...b]; return a.filter((v) => { const i = rest.indexOf(v); if (i === -1) return true; rest.splice(i, 1); return false; }); };
const onPageButUndocumented = onlyIn(offered, documented);
const documentedButNotOnPage = onlyIn(documented, offered);
const detail = onPageButUndocumented.length === 0 && documentedButNotOnPage.length === 0
  ? `same values, different order`
  : [onPageButUndocumented.length ? `shown on the page but missing from the "<info-block>" block: ${onPageButUndocumented.join(", ")}` : "",
     documentedButNotOnPage.length ? `in the "<info-block>" block but not shown on the page: ${documentedButNotOnPage.join(", ")}` : ""].filter(Boolean).join("; ");
expect.soft(documented, `"${attr}" — mismatch between the "<info-block>" block and the options on the page: ${detail}`).toEqual(offered);
```

**Severity:** Architectural debt by default — the check works, but a failure costs the next reader a
trace dig. Not a finding when the message already names the diverging values, or when the value is
scalar and self-evident (`Expected 200, Received 500` needs no expansion). Do not manufacture a
finding for a passing scalar assertion whose message is already concrete.

---

## Every skip and fixme states its cause first

A parked test that does not say *why* is a test nobody can triage. The CI reporter prints the
skip list at the top of every run, and a line like `- [skip] the recent-activity card row and optional
slot render` tells the reader nothing they can act on — they have to open the file to learn
whether it is a feature flag, missing seed data, or a defect somebody forgot.

**Flag as a finding any `test.skip` or `test.fixme` whose reason does not lead with the cause.**

The reason string is `<short cause> — <the longer explanation>`. The short cause comes first
because it is what a human scanning a CI log needs; it names the switch, the missing data, or the
ticket:

```ts
// ✅ cause first — readable straight out of the CI log
"<feature-flag> = false (<app-dir>/src/lib/<feature-file>.ts) — the optional panel and the
 summary card are not rendered, so two of the four assertions here cannot hold"

"no items need action on the seeded account — the attention row only renders when its
 count is non-zero, so there is no link to follow. Data gap, not a defect"

"<ticket-prefix>-1234 — awaiting a product decision on whether the dashboard should have an H1"

// ❌ explanation with no cause, or no reason at all
"the summary row is hidden when nothing needs action"
test.skip("the recent-activity card row and optional slot render", { tag: [...] }, async () => {})
```

Three things to check:

1. **An unconditional `test.skip(title, …)` carries no reason of its own.** Playwright pushes a
   bare `{ type: 'skip' }` annotation with an empty description, so the CI log shows the title and
   nothing else. The reason has to be declared explicitly in the test's `annotation` option:
   `{ tag: [...], annotation: { type: "skip", description: "<cause> — <explanation>" } }`.
2. **A conditional `test.skip(cond, reason)` already has the slot** — the finding is when the
   `reason` opens with the consequence instead of the cause.
3. **A `fixme` with no ticket has no owner and no expiry**, so nothing ever retires it. Either the
   reason names a ticket, or the finding is that one needs filing. Prefer quarantine (`<quarantine-tag>`
   + a row in `<quarantine-register>`) over `fixme` for anything with a ticket — that
   lane at least runs the test and reports when it starts passing.

Same bar for the *type* of park: a skip that is really a ticketed defect belongs in quarantine or
under `test.fail`, per `playwright-core §skip-vs-fixme`. This section is about the reason text;
that one is about the mechanism.

---

## Comment locality — ≤5 lines in the code file, the rest in the folder README

A reader scanning `<e2e-dir>` for the test should not have to page past a 60-line essay to reach
the first `test(`. Long narrative belongs next to the folder, not at the top of a spec.

**A single comment block is ≤5 lines. Past that, the explanation moves to a `## File notes` section
in the `README.md` of the folder the code file lives in.** A "block" is one `/* */`/JSDoc block or
an unbroken run of `//` lines.

- **Per block, not per file.** Four separate 3-line "why" notes in one spec are fine. The finding is
  a *single* block that runs long — a module header, a fixture rationale, a multi-paragraph
  justification.
- **Judgment at the margin.** A genuinely load-bearing 6–7-line constraint is not a finding — the
  cap is "≤5; past that, move it", which fires on a 30-line header and stays quiet on a tight 6.
  Flag the essays, not the borderline.
- **Overflow home.** The folder's own `README.md`, created if absent. One README serves every file
  in that *one* folder — never reach up or down a directory. Put the rationale under a `## File
  notes` heading so it does not dilute the canon rules the rest of the README (and Step 1) treats as
  law.
- **Two-way link, or it rots.**
  - *README → code*: the `## File notes` entry's heading **names the file and the symbol** it
    explains — `### item-summary.ts — snapshot, not live copy`. Without the
    back-reference the note lingers after the file is renamed or deleted and nothing points at it.
    The back-reference is what makes the drift reviewable.
  - *Code → README*: the block shrinks to a ≤1-line pointer whose anchor is the one GitHub derives
    from that heading —
    `// Why a snapshot, not a live copy: see ./README.md#item-summaryts--snapshot-not-live-copy`.
    GitHub lowercases the heading, drops punctuation (the `.` and the `—`), and turns runs of spaces
    into hyphens, so `.ts` becomes `ts` and ` — ` becomes `--`. Copy the anchor from the rendered
    README rather than hand-writing it; a link to `#snapshot-not-live-copy` will not resolve.
- **Scope: files in this review's scope only.** Existing specs may carry long headers; do not
  flag them all at once. Apply the rule to the changed/new files under review, so the suite converts
  gradually — the same way the debt-marker rule was allowed to land green rather than demanding a
  repo-wide cleanup first.

This is a review finding and an always-on convention (`<e2e-dir>/CLAUDE.md` directive 6),
not a blocking gate — comment shape is judgment, and a wrong-firing gate is worse than none.

---

## Scope boundary

- **App code is off-limits.** A finding in `<app-dir>/src/` or `<backend-dir>/` is reported and routed to
  the owning team, never fixed here. Adding a missing `data-testid` is the one sanctioned test
  affordance, and it is still a proposal in a review.
- **A confirmed app bug becomes a ticket**, not a loosened assertion and not a `skip`. Never
  suggest weakening a test to make it pass — that is the failure mode this whole canon exists to
  prevent.
