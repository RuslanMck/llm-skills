---
name: plan-to-checklist
description: Turn a plan, design note, or investigation into (1) a phased, dependency-ordered action checklist and (2) a seam-based phase→ticket distribution that resists over-slicing. Filing the resulting tickets is always delegated to Linear rules (Linear field rules + a body format), never hand-written here. Use when asked to "make a checklist", "phase this plan", "what actions are needed", "how many tickets", or "ticket distribution" — especially after a scoping/investigation conversation.
---

# plan-to-checklist

Two-step transform: prose plan → **checklist** → **ticket distribution**. Do step 1 always; do step 2 when the user asks about tickets/slicing.

## Placeholders

- `<linear-cli>` — the Linear command-line tool used to file tickets.
- `<env-file>` — the file that holds the Linear API key for that tool.
- `<team-label>` — the label every ticket from the owning team carries.
- `<impl-body-template>` — the body template for umbrella and implementation tickets.
- `<bug-body-template>` — the body template for bug tickets.
- `<source-dir>` — the folder where real source and test file paths live.

## Step 1 — Plan to phased checklist

Rules:
- **Order by dependency, not by narrative.** The enabling/shared change (a schema, a helper, a queue record, a parser) comes first as its own phase because everything else consumes it. Verification comes last.
- **One phase = one coherent unit of work** that can be reviewed together. Number them; a `.5` phase is fine for an enabler slotted between two majors.
- **Every item is a checkbox `- [ ]`, imperative, concrete.** Name the real file path / function / spec where known (`<source-dir>/...`, a test title). No vague "improve X".
- **Surface the guardrails as their own items**, not prose: back-compat of a shared change, soft-vs-hard assertion policy, "don't make it red-by-design against open tickets", credentials stay in their canonical home.
- **Prerequisites that are already live reds get an early, standalone phase** — they must be shippable before the epic starts.
- End with a short "decide before implementation" note listing the 1–3 genuine open choices, and offer to write the plan to `docs/plans/` and/or file tickets (both need explicit go).

Output shape: bold phase headers (`**Phase N — title**`) each followed by its `- [ ]` items.

## Step 2 — Checklist to ticket distribution

Default assumption: a task-per-phase list is **over-sliced**. Collapse it by **seam**, not by size.

Slice a new ticket only at a real seam:
- **Ownership** — a different team/person owns it (test infrastructure vs application code).
- **External dependency / rollback** — it ships or reverts on its own timeline (a live-red fix, a flag).
- **Vertical journey** — one end-to-end user path for one user type is ONE ticket, even if it spans many phases.

Never slice for size, and never create these as separate tickets:
- **CI wiring** and **green-run verification** — they are the **DoD inside the impl ticket**, never a standalone "CI"/"QA gate" ticket.
- A shared enabler used by two journeys → one **foundation** ticket (not one per consumer).

Keep separate on purpose:
- A prerequisite that is **already failing in CI** — its own ticket so it merges before the epic.

Structure: one **umbrella** (parent, tracking) + N **children**, linked `parentId`. Wire `blockedBy`: foundation → journeys; a shared-prereq fix → the legs that consume it. Two journeys are parallel once the foundation lands.

Present as a table: `Ticket | Phases | Seam rationale | Blocks`. Offer a leaner fallback (fold the prereq into foundation) with the tradeoff stated.

## Filing the tickets — always via Linear

Never hand-write Linear tickets from this skill. When the user says to file them, follow these rules, in this order:

1. **Tool path** — Prefer the `<linear-cli>` tool; if `<env-file>` has no `LINEAR_API_KEY`, fall back to Linear MCP `save_issue` (needed anyway when a project + multiple labels must be set on create).
2. **Field rules** — project = a dated outcome bucket (never a retired bucket — ask if none fits), labels = work-type + `<team-label>` + one Type + one Concern, state `Backlog`, no cycle, unassigned. **This file wins on fields over any body format.**
3. **Body format** — decides what each ticket *says*: the umbrella + impl tickets follow `<impl-body-template>`; a bug follows `<bug-body-template>`. Do NOT free-hand the bodies.

Layering: the field rules govern the fields, the body format governs the prose. After any MCP `save_issue` update, re-read each ticket and confirm labels/project/parent did not drop.

## Worked example (reference shape, not a template to copy)

A "cover the whole feature end-to-end" plan produced 8 phases (shared fixture → read helper → existing-bug fix → unauthenticated path → authenticated path → soft-assert policy → CI → verify). It collapsed to **umbrella + 4 children**: Foundation (fixture + read helper), Existing failure (live red, standalone), Unauthenticated journey (phases + its CI/verify DoD), Authenticated journey (phases + DoD). CI and verify phases folded into the journey tickets; the existing failure stayed separate because it was already red.
