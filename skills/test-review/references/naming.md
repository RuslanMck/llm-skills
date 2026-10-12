# The naming pass

Names are the check no tool performs, and the one most often skipped. When you wrote the code under
review, run this pass **before** the correctness hunt: the author's own reading of a name is the
least reliable. Every hit is at least **Architectural**. Report all naming findings in the report's
`Naming` section (see `report-format.md`), never under a severity heading.

## 1. The method: read each name cold

Take each name the diff introduces or renames, with the code covered: no file, no type, no
surrounding lines. Write one line saying what it holds, or what it does.

- If the line comes out clean, the name passes.
- If you need the body, the type signature, or a usage site to write that line, **the name is the
  finding**. Report it with `file:line`, the name, and the plain-language line the name should have
  supported.
- **Critical** when the name says one thing and holds another. Misleading names are worse than vague ones.

Scope: variables, constants, parameters, callback parameters, functions, helpers, methods, types,
fields, and test titles and step titles. Cover every folder the diff touches: specs, support,
page objects, components, fixtures, services, schemas, test data.

**There is no denylist.** A list of bad words catches only the words somebody already thought of.
The names that slip through are the ones nobody listed. The greps below are a floor, not the method.

## 2. Test titles (behaviour-first, plain language)

A title that reads as implementation only (no subject, no outcome, jargon only, or a ticket number)
is **Architectural**. **Critical** when it is actively misleading, such as a title naming the wrong
endpoint.

- **No subject or no outcome.** `returns 200 + ItemSchema`, `responds within 2000 ms`. You cannot tell
  what happens or why it matters. Rewrite as *what happens* and *the expected outcome*, with the
  technical scope in trailing parentheses: `Items load with every expected field (GET /items → 200)`.
- **Jargon only.** Schema class, verb and path with no domain words (`response body parses against the
  item schema`). Lead with domain language; keep schema, field and status detail inside the parentheses.
- **Mechanism instead of intent.** `… parses strictly`, `… is structurally valid`. Say what that means:
  `… loads with a complete, valid structure`.
- **Ticket ID or bare step number in the title.** `PROJ-1186 — …`, `Step 1 — …`. Tickets belong in a
  tag or comment. A journey step is named by its purpose, not its number.

Remedy: always a rewrite to the behaviour-first template. Never delete the technical detail. Move it
into the parentheses.

Quick grep (example; adapt the prefixes to the project's conventions):

```bash
# Substitute <test-dir> with the test folder you discovered.
cd <test-dir> && grep -RnE "test\(\s*['\"](returns |responds |Step [0-9]|[A-Z]+-[0-9]+ )" . || true
```

## 3. Step titles (`test.step`)

Step titles come in two kinds. Check each one against its kind.

- **An action or setup step** contains no assertion (it navigates, clicks, fills, seeds or intercepts).
  It starts with an imperative verb. A setup step that starts with the assertion verb is a wrong-kind
  finding.
- **An assertion step** contains an assertion. Its title starts with the project's assertion verb
  (`Verify` as the example used in the source project). An assertion step without that verb is a finding.
- **Retired prefixes.** An old prefix such as `Assert:` left in a title is **Architectural**. Rewrite to
  the current convention.
- **Mechanism instead of meaning.** `Verify body parses against the schema` states the mechanism. Say
  the data's meaning: `Verify the item data comes back in the expected shape`.
- **Value not interpolated.** A value or state check whose title does not show the actual value gives
  the reader nothing when it fails. Use the `Expected: X, Actual: ${actual}` form for value and state
  checks, so the step title carries both sides.

Discovery: find the project's step-title convention in the test-folder README or the existing specs.
If it has none, require only the distinction above: action steps and assertion steps are told apart
by their titles.

## 4. Variable and helper names

Canon: the project's specs README, if it has a "variable naming" section. Otherwise these rules
stand. They are reader-centric: a name carries a subject, and team vocabulary wins. Each is
**Architectural**, **Critical** when the name is actively misleading.

- **Generic state noun.** `const snapshot = …`, `start`, `states`, `result`, `data`, `res`, `tmp`,
  `info` holding captured state. The name must carry subject and moment: `groupStatesOnLoad`,
  `finishingGroupAfterReveal`.
  ```bash
  # Substitute <test-dir> with the test folder you discovered.
  grep -RnE "const (snapshot|start|states|result|data|res|tmp|info)\s*=" <test-dir>/specs <test-dir>/support
  ```
- **Invented domain term.** A concept the DOM or the team already names, renamed by the author. If the
  attribute is `data-option-group`, the variable is `optionGroup`, not `axis`. The team's word wins.
- **Mechanism name.** A variable named for the loop rather than its meaning for the test:
  `swept` / `notSwept` should be `optionsToClick` / `optionsLeftUnclicked`.
- **Near-twins in one scope.** Two almost identical names holding unrelated things (`reveal` and
  `revealed`). Rename so each says what it holds.
- **Undefined abstraction.** An abstract term used without a definition at its declaration
  (`transitions`: transitions from what to what?). Add a one-line definition where it is declared, or
  rename it to what it is.
- **Bare comparative or moment.** A name that gives position but never subject: `low` / `high`,
  `min` / `max`, `before` / `after`, `prev` / `next`, `first` / `last`, `counts`, `count`, `counted`,
  `total`, `reconciled`, `here` / `there`, `res`. Read `low <= high` and ask: low *what*? Rename to
  `<subject><Position>`: `smallestBucketSizeSeen`, `bucketSizesBeforeRender`, `renderedChipCount`,
  `itemCountPerCategory`. The subject may be dropped **only** inside a one-line lambda whose argument is
  unambiguous (`(item) => item.id`).
  ```bash
  # Substitute <test-dir> with the test folder you discovered.
  grep -RnE "\b(const|let) (low|high|min|max|before|after|prev|next|first|last|counts|count|counted|total|reconciled|here|there|res)\b\s*[=:]" <test-dir>/specs <test-dir>/support <test-dir>/pages <test-dir>/components <test-dir>/fixtures
  ```
- **Carve-out: `expected` and `actual`.** These are the sanctioned names for an oracle-versus-observed
  pair, and they match the step-title form. They are **not** findings on their own. Flag them only when
  one scope holds several different expectations, where `expected` cannot say which one.
- **Scope of these rules.** They bind support, page objects, components and fixtures exactly as they
  bind specs. A vague name in a shared helper is worse, because every caller inherits it. Check the
  file's own declarations **and** the names it destructures from the helpers it calls.
  `const { rendered, lowest, highest } = helper()` is a finding against the helper's return type,
  reported against the helper.
- **Page-object locator names end in the element's role.** `quoteLink`, `reorderButton`, `…Card`,
  `…Modal`, `…Text`. A name like `quoteAction` that needs a comment to say "it's a link" is a finding.
  A comment that restates the name is deleted.
- **Predicate names read as questions.** See `checks.md` §8.

**Run the greps in this section on every review, then read the remaining declarations by eye.** A
review that passes `const counts = new Map()` or `const low = Math.min(…)` has not run the naming pass.

## 5. Test name is the failure message

The first thing a CI reader sees is the test name, so a non-engineer should understand it.
`login` is useless. `returns 200 + AuthSchema` is jargon. `A valid email returns a generic success
message (POST /auth/forgot-password → 200)` describes the behaviour and puts the technical scope in
the parentheses. The stable trace ID goes in a tag, not the title. Titles that do not describe
behaviour in plain language are **Architectural** (§2).

## 6. Diagnosis line, for the report

When you report a naming finding, the diagnosis sentence states the defect, not the category:

- Good: `` `groups` says its shape (a map) but not its subject; read on its own it could hold anything. ``
- Not good: `naming issue`.

The remedy is the rename, stated concretely: `Rename to recordsByField.`
