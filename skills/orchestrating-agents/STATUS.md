---
name: status
description: "Canonical template and rendering rules for the task-centric status display."
---

# Agent Status Display

## Trigger Conditions

Render the status display whenever:

- The human asks anything resembling a status query: "what are the agents doing", "status update", "show me agent status", "how is the work going", "what's in progress", etc.
- The `/status` skill is invoked.

Always respond with tables. Do not summarise in prose instead of or in addition to tables. Never use bulleted lists, numbered lists, or any non-table format — every piece of status data must appear inside a table row.

## Table Format

Each status section is a **multi-column markdown table** — one row per entity. This lets the eye scan rows horizontally and spot patterns across tasks at a glance.

URLs do not render well in table cells, so all PR links use a **footnote stub** (`[N]`) in-line, with the full URL listed below the table.

## Tasks Table

Primary view. Always shown when a plan is loaded.

```
## Tasks

| Task | Status | Commit |
|------|--------|--------|
| T-1: Add auth flow | done | a1b2c3d |
| T-2: API client | in_progress | |
| T-3: Cache layer | ready | |
| T-4: Dashboard | blocked on T-2 | |
```

**Columns:**

| Column | Source | Notes |
|--------|--------|-------|
| Task | `task.id` + `task.title` | Format: `T-{id}: {title}`. Truncate title to 30 chars if needed. |
| Status | Derived from task state | See Status Values below. |
| Commit | `task.result.commit_sha` | Abbreviated SHA (7 chars). Blank if not yet committed. |

### Status Values

| Value | When to use |
|-------|-------------|
| `done` | Task status is `done` |
| `in_progress` | Task status is `in_progress` |
| `ready` | Task status is `pending` and all `depends_on` are `done` |
| `blocked on T-{id}` | Task status is `pending` or `blocked` with unmet dependencies (show the first unmet dependency) |
| `cancelled` | Task status is `cancelled` |
| `failed` | Task status is `failed` |

## Plan Card

Used in the startup greeting and completion summary when a plan summary is warranted:

```
| Plan: {plan_id} |
|---|
| **Project:** {title} |
| **Tasks:** {done}/{total} done ({queued} queued) |
```

---

## Rendering Rules

### Tasks Table

1. **Row inclusion:** All tasks in the plan. Omit `cancelled` tasks unless the human asks for a full plan view.
2. **Sort order:** `in_progress` → `ready` → `blocked` → `done` → `failed` → `cancelled`.
3. **Empty state:** If no plan is loaded, omit the Tasks section entirely.

### No active plan

If no plan is loaded, display exactly:

> No active plan. Give me an assignment to get started.

### Single entity

If only one task exists, still render it as a table row (do not switch to prose).
