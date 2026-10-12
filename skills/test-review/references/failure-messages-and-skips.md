# Failure messages, skip reasons, and comment locality

Three canons that decide what a reader sees when something goes wrong: the assertion message, the
skip or fixme reason in the run log, and the comment block at the top of a file.

---

## 1. Failure messages state the facts, not the rule

When an assertion fails, its message and the `test.step` title it surfaces under are the whole signal
a human gets in the CI summary, the reporter's failed list, and the error-context file. Usually nobody
opens the trace. A message that only restates the invariant reads the same on every failure. It tells
the reader a contract exists, not which data broke it, and forces them to re-derive the diff by hand.

**Canon: a good failure message**

- **States actual versus expected as concrete values, not only the invariant.** Name the items that
  diverged, and the direction: present but unexpected, expected but missing, or the same set in the
  wrong order. The message is the conclusion, not raw material the reader must process.
- **Is specific to this failure.** If two different failures of one assertion produce an identical
  string, the string is under-informative.
- **Reads in domain language.** The reader may be a product person or a content editor.
  `shown on the page but missing from the summary block: <value>` beats `the record must list the
  same values as the source`. `expected true` or `toEqual failed` with no context is the worst case.
- **Points at the cause, not the mechanism.** Say where to look ("missing from the summary block"),
  not what the matcher did ("toEqual failed").
- **Stays honest to the assertion.** The message may be richer than the check, but it must never claim
  more or less than what failed. The matcher is unchanged; only the narration improves.
- **Lands where the reader lands.** The reporter surfaces the assertion message (the second argument to
  `expect`) and the failing step title. A diff printed only to the console, or only in a step title while
  the assertion message stays generic, does not count. Compute it and put it in the message. When a
  shared helper owns the assertion, the message duty lives in that helper. A spec that passes it a bare
  value cannot add context afterwards.

**Before and after (the shape to require).** Names are examples.

```ts
// Restates the rule: identical on every failure, forces a trace dig.
expect.soft(summaryItems, `"${field}" must list the same values, in the same order`).toEqual(pageItems);

// Names the diverging values and the direction, in domain words.
// Diff as a multiset (count occurrences), not with includes(): a value repeated on one side only
// would otherwise empty both filters and be mislabelled "same values, wrong order".
// If the project has a shared list-diff helper, use it. This is what it does.
const onlyIn = (a: string[], b: string[]) => {
  const rest = [...b];
  return a.filter((v) => {
    const i = rest.indexOf(v);
    if (i === -1) return true;
    rest.splice(i, 1);
    return false;
  });
};
const onPageNotInSummary = onlyIn(pageItems, summaryItems);
const summaryNotOnPage = onlyIn(summaryItems, pageItems);
const detail =
  onPageNotInSummary.length === 0 && summaryNotOnPage.length === 0
    ? 'same values, different order'
    : [
        onPageNotInSummary.length ? `shown on the page but missing from the summary block: ${onPageNotInSummary.join(', ')}` : '',
        summaryNotOnPage.length ? `in the summary block but not shown on the page: ${summaryNotOnPage.join(', ')}` : '',
      ].filter(Boolean).join('; ');
expect.soft(summaryItems, `"${field}" — mismatch between the summary block and the page: ${detail}`).toEqual(pageItems);
```

**Severity.** **Architectural** by default. The check works, but a failure costs the next reader a trace
dig. It is not a finding when the message already names the diverging values, or when the value is scalar
and self-evident (`Expected 200, Received 500` needs no expansion). Do not manufacture a finding for a
passing scalar assertion whose message is already concrete.

---

## 2. Every skip and fixme states its cause first

A parked test that does not say why is a test nobody can triage. The reporter prints the skip list at
the top of every run. A line such as `[skip] the summary card row and optional slot render` tells the
reader nothing actionable. They must open the file to learn whether it is a switch, missing seed data, or
a defect someone forgot.

**Flag as a finding any skip or fixme whose reason does not lead with the cause.**

The reason reads `<short cause> — <longer explanation>`. The short cause comes first, because it is what
someone scanning a CI log needs. It names the switch, the missing data, or the ticket.

```ts
// Cause first: readable straight out of the CI log.
"<feature-flag> is off (src/<feature-file>) — the optional panel and summary card are not rendered, so two of the four assertions cannot hold"
"no items need action on the seeded account — the attention row only renders when its count is non-zero, so there is no link to follow. Data gap, not a defect"
"PROJ-1234 — awaiting a product decision on whether the dashboard should have a top-level heading"

// Explanation with no cause, or no reason at all: a finding.
"the summary row is hidden when nothing needs action"
test.skip("the summary card row and optional slot render", async () => {})
```

Checks:

1. **An unconditional `skip(title, …)` carries no reason of its own.** Playwright records a bare skip
   annotation with an empty description, so the log shows the title and nothing else. Declare the reason
   explicitly: in Playwright, use the `annotation` option, `{ annotation: { type: 'skip', description: '<cause> — <explanation>' } }`.
   In other frameworks, pass the reason string the framework's skip API accepts.
2. **A conditional skip already has the slot.** `skip(condition, reason)` takes the reason as its second
   argument. A finding exists when that reason opens with the consequence instead of the cause.
3. **A fixme needs an owner and an expiry.** Without a ticket it has neither, so nothing retires it. The
   reason must name a ticket or a cause, or the finding is that one needs filing.
   - **If the project has a quarantine or known-issue convention** (look for a quarantine tag, a register
     document, or a known-issue marker in the test-folder README or existing specs), prefer it over fixme
     for anything with a ticket. Quarantine still runs the test and reports when it starts passing.
   - **If it does not**, the skip or fixme reason names the ticket or the cause, and that is the whole rule.

The same bar applies to the type of park. A skip that is really a ticketed defect belongs in quarantine,
or under the framework's known-failure mechanism (Playwright: `test.fail`). `test.fail` runs the test and
fails the run when the test starts passing, so the defect cannot hide. This section covers the reason
text. Whether a park is a quarantine, `test.fail`, or a plain skip is decided by the "type of park" paragraph above; this section covers only the reason text.

---

## 3. Comment locality: at most five lines per block in the code file

A reader scanning the test folder for a test should not page past a 60-line essay to reach the first test.
Long narrative belongs next to the folder, not at the top of a file.

**A single comment block is at most 5 lines.** Past that, the explanation moves to a `## File notes` section
in the `README.md` of the folder the file lives in. A block is one `/* */` or JSDoc block, or one unbroken
run of `//` lines.

- **Per block, not per file.** Four separate three-line "why" notes in one spec are fine. The finding is a
  single block that runs long: a module header, a fixture rationale, a multi-paragraph justification.
- **Judgment at the margin.** A load-bearing six or seven line constraint is not a finding. The rule fires
  on a 30-line header, not on a tight six. Flag the essays, not the borderline.
- **Overflow home.** The `README.md` of that one folder, created if absent. One README serves every file in
  that folder, and never reach up or down the tree. Put the rationale under a `## File notes` heading, so
  it does not dilute the README's canon rules.
  - **If the project has no folder READMEs,** and does not want them, put the overflow in the folder's
    nearest existing docs file, or ask where it should go. Do not invent a new documentation layout.
- **Two-way link, or it rots.**
  - *README to code:* the `## File notes` entry heading names the file and the symbol it explains, for
    example `### item-summary.ts — snapshot, not live copy`. Without the back-reference the note outlives a
    rename or deletion, and nothing points at it.
  - *Code to README:* the block shrinks to a one-line pointer whose anchor matches the heading. If the
    README renders on GitHub, the anchor lowercases the heading, drops punctuation, and turns spaces into
    hyphens, so `.ts` becomes `ts` and ` — ` becomes `--`. Copy the anchor from the rendered README. A
    hand-written guess will not resolve.
    ```ts
    // Why a snapshot, not a live copy: see ./README.md#item-summaryts--snapshot-not-live-copy
    ```
- **Scope: changed and new files only.** Existing files may carry long headers. Do not flag them all at
  once. Apply the rule to the files under review, so the suite converts gradually.
- **Always-on convention, not a gate.** Comment shape is judgment. A wrong-firing gate is worse than none.
  Report it as a finding; do not block on it.

---

## Checklist for this file

- [ ] Each assertion message names the diverging values and direction, not only the invariant.
- [ ] Each message is specific to its failure, and reads in domain language.
- [ ] Each skip or fixme reason leads with the cause or a ticket.
- [ ] Unconditional skips declare their reason; conditional skips open with the cause.
- [ ] Each comment block is at most 5 lines in changed files; longer ones point at the folder README.
