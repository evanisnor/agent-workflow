---
name: status
description: "Canonical template and rendering rules for the worktree-centric status display."
---

# Agent Status Display

## Trigger Conditions

Render the status display whenever:

- The human asks anything resembling a status query: "what are the agents doing", "status update", "show me agent status", "how is the work going", "what's in progress", etc.
- The `/status` skill is invoked.

Always respond with tables. Do not summarise in prose instead of or in addition to tables. Never use bulleted lists, numbered lists, or any non-table format — every piece of status data must appear inside a table row.

## Table Format

Each status section is a **multi-column markdown table** — one row per entity. This lets the eye scan rows horizontally and spot patterns across worktrees, tasks, and PRs at a glance.

URLs do not render well in table cells, so all PR links use a **footnote stub** (`[N]`) in-line, with the full URL listed below the table.

## Worktrees Table

All worktrees — both plan-tracked and independent — appear as rows in one table:

```
## Worktrees

| Branch | Task | Agent | Activity | PR |
|--------|------|-------|----------|----|
| `feat/auth` | T-1: Add auth flow | active | implementing | |
| `feat/api` | T-3: API client | monitoring | CI running | #42 [1] |
| `feat/cache` | T-4: Cache layer | stopped | interrupted | |
| `fix/typo` | | | approved | #44 [2] |
| `chore/deps` | | | no PR | |

[1]: https://github.com/org/repo/pull/42
[2]: https://github.com/org/repo/pull/44
```

**Columns:**

| Column | Source | Notes |
|--------|--------|-------|
| Branch | `task.branch` or worktree ref | Rendered as inline code. Stacking annotations appended: `` `feat/login (on feat/auth)` `` or `` `feat/auth (<- T-5)` ``. |
| Task | `task.id` + `task.title` | Format: `T-{id}: {title}`. Truncate title to 15 chars if needed. Blank for independent worktrees. |
| Agent | Derived from `TaskGet(agent_id)` | See Agent Values below. Blank for independent worktrees and agentless tasks (`agent_id: null`). |
| Activity | Derived from plan state + live PR/CI context | See Activity Values below. |
| PR | `task.pr_url` — render as `#{number} [N]` | Footnote stub with numbered reference. Blank when no PR exists. |

**Footnotes:** Numbered per-section starting at `[1]`. Full URL list immediately below the table, one per line: `[N]: <url>`.

### Independent Worktrees

Worktrees that exist on disk (per `git worktree list --porcelain`) but are not referenced by any plan task's `worktree` field are **independent worktrees**. For each independent worktree (excluding the main worktree):

- **Branch:** from worktree ref (strip `refs/heads/`).
- **Task:** blank.
- **Agent:** blank.
- **Activity:** derived from PR status per [PR_MONITORING.md](PR_MONITORING.md) § Independent PR Activity Derivation. Use `no PR` when no PR is found.
- **PR:** discovered via `gh pr list --head <branch> --json number,url --jq '.[0]'`. Blank if no PR found.

Independent rows sort **after** all plan rows (after the `merged` group).

## Agent Values

The Agent column shows the agent's relationship to the worktree:

| Value | When to use |
|-------|-------------|
| `active` | `TaskGet(agent_id)` returns `running` and Activity is an active-work state: `implementing`, `pre-PR checklist`, `awaiting diff review`, `fixing CI (N/M)`, `stacked — implementing` |
| `monitoring` | `TaskGet(agent_id)` returns `running` and Activity is a passive-wait state: `CI running`, `awaiting review`, `changes requested`, `in merge queue`, `stacking offered` |
| `stopped` | `TaskGet(agent_id)` returns `failed` or `stopped` |

If `agent_id` is null (task adopted into monitoring), leave the Agent cell blank. Show only the Activity value.

## Activity Values

Derived by the Orchestrating Agent from plan state and live PR/CI context. Use the most specific value that applies:

| Activity | When to use |
|----------|-------------|
| `implementing` | No PR open yet, agent writing code |
| `pre-PR checklist` | Task Agent has signalled checklist underway |
| `awaiting diff review` | Task Agent has requested diff approval from human |
| `stacking offered` | Diff approved; Orchestrating Agent has asked human about stacking, awaiting answer |
| `stacked — implementing` | Task is stacked (`stacked: true`); Task Agent is actively implementing |
| `CI running` | PR open, CI checks in progress |
| `fixing CI (N/M)` | Task Agent is applying a CI fix; N = current attempt, M = max |
| `awaiting review` | PR marked ready, no review decision yet |
| `changes requested` | PR reviewer has requested changes, awaiting human approval |
| `reviewer commented` | PR reviewer left comments (not formal change request), awaiting human decision |
| `in merge queue` | PR approved and added to merge queue |
| `merged` | PR merged successfully |
| `interrupted` | Agent stopped; work was incomplete (no PR, or PR is still draft) |
| `unattended` | Agent stopped; PR is open and in flight |
| `escalation required` | CI fix limit exceeded, unrecoverable error, or worktree path not registered |
| `no PR` | Independent worktree; no PR found |
| `CI running` | Independent PR; CI in progress |
| `awaiting review` | Independent PR; waiting for reviewer |
| `approved` | Independent PR; approved + CI passing, awaiting human merge decision |
| `changes requested` | Independent PR; reviewer requested changes |
| `reviewer commented` | Independent PR; reviewer left comments |
| `CI failed` | Independent PR; CI failed |
| `in merge queue` | Independent PR; in merge queue |
| `merge conflict` | Independent PR; conflict in merge queue |
| `ejected` | Independent PR; ejected from merge queue |
| `closed` | Independent PR; closed without merging |
| `merged` | Independent PR; merged (briefly, before cleanup) |

For tasks with `agent_id: null`, derive activity from `check-pr-status.sh` using the same mapping as Independent PR Activity Derivation ([PR_MONITORING.md](PR_MONITORING.md) § Independent PR Activity Derivation).

### Stopped-Agent Activity Derivation

When `TaskGet(agent_id)` returns `failed` or `stopped` for a task with `worktree` set:

1. If `task.pr_url` is set and the PR is open (not draft): **`unattended`**
2. Otherwise: **`interrupted`**
3. Verify the worktree path is registered via `git worktree list --porcelain`. If the path is not found, use **`escalation required`** instead.

## Queued Table

Render one table below the Worktrees Table when there are tasks without worktrees that should be displayed. If there are no queued tasks, omit the section entirely.

```
## Queued

| Task | Title | Status |
|------|-------|--------|
| T-5 | Dashboard widgets | ready |
| T-6 | Analytics pipeline | blocked on T-3 |
```

**Columns:**

| Column | Source | Notes |
|--------|--------|-------|
| Task | `task.id` | Format: `T-{id}` |
| Title | `task.title` | Truncate to 30 chars if needed |
| Status | Derived from dependencies | `ready` if all `depends_on` are `done`; `blocked on T-{id}` otherwise (show the first unmet dependency) |

## Pending Reviews Table

Render one table below the Queued section (or below the Worktrees Table if Queued is omitted) when there are entries in the pending reviews list. If there are no pending reviews, omit the section entirely.

```
## Pending Reviews

| PR | Author | Status |
|----|--------|--------|
| #50 -- Fix auth redirect [1] | @alice | ready |

[1]: https://github.com/org/repo/pull/50
```

**Columns:**

| Column | Source | Notes |
|--------|--------|-------|
| PR | `pr_number` + `title` | Format: `#{number} -- {title} [N]`. Truncate title to 30 chars if needed. Footnote stub for URL. |
| Author | `author` | Format: `@{author}` |
| Status | Review status | See status values below. |

**Footnotes:** Numbered per-section starting at `[1]`. Full URL list immediately below the table.

**Status values:**

| Value | Meaning |
|-------|---------|
| `preliminary` | Review Agent running; analysis not yet ready |
| `ready` | Analysis complete; awaiting human |
| `reviewing` | Diff pane open; human is actively reviewing |
| `approved` | Human approved; PR left for author to merge |

## Plan Card

Used in the startup greeting and completion summary when a plan summary is warranted:

```
| Plan: {plan_id} |
|---|
| **Project:** {title} |
| **Tasks:** {done}/{total} done ({active} active, {queued} queued) |
```

---

## Rendering Rules

### Worktrees Table

1. **Row inclusion:** Every task with `worktree` set in the plan, plus all independent worktrees (see Independent Worktrees above). Include `done` tasks from the current session briefly (with `merged` activity) until the worktree is cleaned up.
2. **Sort order:** `active` → `monitoring` → `stopped` → `merged` → independent (monitored: any activity except `no PR`) → independent (`no PR`).
3. **Empty state:** If no plan worktrees exist but independent worktrees exist, still render the Worktrees Table (independent only). If no worktrees of any kind exist and a plan is loaded, omit the Worktrees section header — only show Queued.

### Queued section

1. **Row inclusion:**
   - `pending` tasks with all `depends_on` done — show Status as `ready`.
   - `pending` tasks with unmet dependencies and `blocked` tasks — show Status as `blocked on T-{id}`.
   - Omit `cancelled` tasks unless the human asks for a full plan view.
2. **Sort order:** `ready` → `blocked`.
3. **Empty state:** If no queued tasks, omit the section.

### Pending Reviews

1. Render when there are entries in the pending reviews list. Omit entirely when empty.

### No active plan

If no plan is loaded and independent worktrees exist, render the Worktrees Table (independent only) followed by:

> No active plan. Give me an assignment to get started.

If no plan is loaded and no independent worktrees exist, display exactly:

> No active plan. Give me an assignment to get started.

### Single worktree

If only one worktree is active, still render it as a table row (do not switch to prose).
