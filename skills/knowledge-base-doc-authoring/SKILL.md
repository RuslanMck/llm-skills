---
name: knowledge-base-doc-authoring
description: Write a document for the <knowledge-base> — naming, the .meta.md sidecar, drop-zone rules, and how to split one body of knowledge into linked pages. Use when asked to "put this in the <knowledge-base>", "make a <knowledge-base> doc", or to prepare repo docs for <knowledge-base> upload.
---

# Authoring docs for the <knowledge-base>

## Placeholders

- `<knowledge-base>` — the name of your knowledge base system (e.g. "Wiki", "Vault", "Notes")
- `<knowledge-base-dir>` — local filesystem path to the knowledge base clone (e.g. `~/Projects/my-kb`)
- `<source-dir>` — the folder where raw/unprocessed source files live; read-only except for the drop zone
- `<drop-zone-dir>` — the subfolder inside `<source-dir>` where new files are deposited for ingestion
- `<protected-dir>` — the folder that requires human approval before any changes are merged
- `<rules-file>` — the vault-level rules file that overrides this skill
- `<dead-letter-dir>` — the folder for files the ingest cannot process
- `<author-initials>` — the initials of the human author (not the agent)
- `<target-dir>` — the folder in the knowledge base where a published doc is expected to land (used in `target_path`)

The <knowledge-base> is a **separate vault and git repo**, not part of the project repo. Local clone:
`<knowledge-base-dir>`. Pass the path explicitly.

**Read the vault's own rules first — they win over anything here:** `<rules-file>`,
`CLAUDE.md`, `AGENTS.md` at the vault root. They change; this skill is a summary of them plus the
conventions the existing files actually follow.

## The hard rules (from `<rules-file>`)

1. **Never edit anything under `<source-dir>/`.** You may only *add* files to
   `<source-dir>/<drop-zone-dir>/`. An ingest process moves them onward.
2. **One ingest = many small linked pages, not one giant page.** A 400-line dump is the wrong
   shape even when every line is true.
3. **`<protected-dir>/` is sacred** — anything targeting it needs human approval before merge.
   Say so explicitly rather than assuming.
4. **Filename:** `YYYY-MM-DD_<drop-type>_<short-slug>_<author-initials>.md`.
5. **Sensitive content** (`sensitivity: restricted`, `.confidential`) is *summarised, never
   quoted*, and never linked from public-facing wiki pages.
6. Unprocessable files go to `<dead-letter-dir>/` with a reason — no silent failures.

## Every drop is TWO files

`<name>.md` — the document. **No YAML frontmatter.** It opens with a heading naming its type and
subject, then prose:

```markdown
# Definition: Widget Inventory

The **Widget Inventory** is the append-only table (`widget_events`) that is …

**Usage:** …

**Constraints:** …
```

`<name>.meta.md` — the sidecar telling the ingest what this is. Keys observed in use (`---` fences
appear on some and not others; match the nearest sibling):

| Key | When | Notes |
|---|---|---|
| `drop_type` | always | `definition` · `brief` · `plan` · `adr` — reuse an existing value, don't invent one |
| `term` | definitions | the exact term being defined |
| `title` | plans, briefs | human title |
| `decision` | ADRs | the decision in one sentence |
| `target_path` | when you know where it lands | e.g. `<target-dir>/<slug>.md` |
| `status` / `version` / `approvers` | plans, ADRs | `accepted`, `1.0`, `[<approver>, <approver>]` |
| `source` | always | which conversation/process produced it |
| `session_context` | always | short slug grouping related drops |
| `notes` | optional | block scalar (`notes: |`) for caveats, supersessions, what was deliberately left out |

## Procedure

1. **Draft in the project repo first** (e.g. `docs/<area>/`), where it sits next to the code it
   describes and gets reviewed with it. The <knowledge-base> copy is a *publication* of that, not the
   original. Check whether the repo doc already exists and extend it — a second file on the same
   subject is worse than a long one.
2. **Split by subject, not by length.** One page per concept a reader would search for
   (a definition, a decision, a flow, a failure mode). Link them with `[[wikilinks]]`. If you
   cannot name a page in a few words, it is two pages.
3. **Name and pair each file** per the conventions above. Author initials are the human's, not
   yours.
4. **Copy into `<source-dir>/<drop-zone-dir>/`**, then commit and push from the vault clone. Never
   touch other folders directly.
5. **Report** the filenames added and anything that needs human approval (sacred folder, restricted
   content).

## What makes a <knowledge-base> doc worth having

- **Date every empirical claim, and name the evidence.** "Reproduced 4/4 on staging 2026-08-11,
  items X, Y, Z" outlives "this is broken". A future reader must be able to re-check you.
- **Mark evidence strength.** Distinguish a repeated observation from a single one, and both from a
  code-read or a stakeholder statement. Collapsing that distinction is how a guess becomes folklore.
- **State precedence when sources disagree** — which source wins, and why.
- **Record what is still unknown**, as its own section. An honest gap list is the most useful part
  of a knowledge base, and the part most often omitted.
- **Keep corrections visible.** When a later fact overturns an earlier one, say so and leave the
  old claim struck rather than silently deleting it — otherwise the same wrong turn gets taken
  again.
- **Write for someone with no context**: expand the acronym once, name the file path, say which
  system a term belongs to.

## Anti-patterns

- A single page covering an entire domain (rule 2).
- Inventing frontmatter inside the `.md` — the sidecar carries metadata.
- A new page duplicating an existing one instead of extending it; search the vault first
  (`grep -rl "<term>" --include="*.md"`).
- Writing to `<protected-dir>/` or any non-drop-zone folder without approval.
- Quoting restricted material to "preserve fidelity".
- Undated claims, and confident prose over thin evidence.
