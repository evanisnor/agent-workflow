---
name: status
description: "Canonical template and rendering rules for the worktree-centric status display."
---

# Agent Status Display

## Trigger Conditions

Render the status display whenever:

- The human asks anything resembling a status query: "what are the agents doing", "status update", "show me agent status", "how is the work going", "what's in progress", etc.
- The `/status` skill is invoked.

Always respond with cards. Do not summarise in prose instead of or in addition to cards. Never use bulleted lists, numbered lists, or any non-card format — every piece of status data must appear inside a card.

## Card Format

Each card is a **single-column markdown table** — the header row is the card's identity, body rows are labeled fields. This gives table borders for visual structure while keeping content narrow enough to avoid terminal wrapping.

## Worktree Cards

Render one card per worktree:

```
| `{branch}` |
|---|
| **Task:** T-{id}: {title} |
| **Agent:** {agent} · **Activity:** {activity} |
| **PR:** #{number} |
| {pr_url} |
```

**Rows:**

| Row | Source | Notes |
|-----|--------|-------|
| Header | `task.branch` | Rendered as inline code. This is the worktree's identity. If `task.stacked: true`, append ` (on {parent_branch})`. If the task has stacked dependents, append ` (← T-{child_id})` instead (comma-separated if multiple). |
| Task | `task.id` + `task.title` | Format: `T-{id}: {title}`. Truncate title to 25 chars if needed. |
| Agent · Activity | Derived from `TaskGet(agent_id)` + activity classification | See Agent Values and Activity Values below. |
| PR | `task.pr_url` — render as `#{number}` | Omit this row and the URL row when no PR exists. |
| URL | `task.pr_url` — full URL on its own line | Omit when no PR exists. Keeps the URL clickable without truncation. |

### Independent Worktree Cards

Worktrees that exist on disk (per `git worktree list --porcelain`) but are not referenced by any plan task's `worktree` field are **independent worktrees**. For each independent worktree (excluding the main worktree):

```
| `{branch}` |
|---|
| **Activity:** {activity} |
| **PR:** #{number} |
| {pr_url} |
```

- Omit Task row (no plan task).
- Omit Agent label (just `**Activity:** {activity}`).
- `{activity}` is derived from PR status per [PR_MONITORING.md](PR_MONITORING.md) § Independent PR Activity Derivation. Use `no PR` when no PR is found.
- PR discovered via `gh pr list --head <branch> --json number,url --jq '.[0]'`. Omit PR and URL rows if no PR found.

Independent cards sort **after** all plan cards (after the `merged` group).

## Agent Values

The Agent field shows the agent's relationship to the worktree:

| Value | When to use |
|-------|-------------|
| `active` | `TaskGet(agent_id)` returns `running` and Activity is an active-work state: `implementing`, `pre-PR checklist`, `awaiting diff review`, `fixing CI (N/M)`, `stacked — implementing` |
| `monitoring` | `TaskGet(agent_id)` returns `running` and Activity is a passive-wait state: `CI running`, `awaiting review`, `changes requested`, `in merge queue`, `stacking offered` |
| `stopped` | `TaskGet(agent_id)` returns `failed` or `stopped` |

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
| `CI failed` | Independent PR; CI failed |
| `in merge queue` | Independent PR; in merge queue |
| `merge conflict` | Independent PR; conflict in merge queue |
| `ejected` | Independent PR; ejected from merge queue |
| `closed` | Independent PR; closed without merging |
| `merged` | Independent PR; merged (briefly, before cleanup) |

### Stopped-Agent Activity Derivation

When `TaskGet(agent_id)` returns `failed` or `stopped` for a task with `worktree` set:

1. If `task.pr_url` is set and the PR is open (not draft): **`unattended`**
2. Otherwise: **`interrupted`**
3. Verify the worktree path is registered via `git worktree list --porcelain`. If the path is not found, use **`escalation required`** instead.

## Queued Task Cards

Render one card per queued task below the Worktree Cards section when there are tasks without worktrees that should be displayed. If there are no queued tasks, omit the section entirely.

```
## Queued

| T-{id} |
|---|
| **Title:** {title} |
| **Status:** {status} |
```

**Rows:**

| Row | Source | Notes |
|-----|--------|-------|
| Header | `task.id` | Format: `T-{id}` |
| Title | `task.title` | Truncate to 30 chars if needed |
| Status | Derived from dependencies | `ready` if all `depends_on` are `done`; `blocked on T-{id}` otherwise (show the first unmet dependency) |

## Pending Review Cards

Render one card per pending review below the Queued section (or below the Worktree Cards if Queued is omitted) when there are entries in the pending reviews list. If there are no pending reviews, omit the section entirely.

```
## Pending Reviews

| #{number} — {title} |
|---|
| **Author:** @{author} · **Status:** {status} |
| {pr_url} |
```

**Rows:**

| Row | Source | Notes |
|-----|--------|-------|
| Header | `pr_number` + `title` | Format: `#{number} — {title}`. Truncate title to 30 chars if needed. |
| Author · Status | `author` + `status` | See status values below. |
| URL | `pr_url` — full URL on its own line | Keeps the URL clickable. |

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

### Worktree Cards

1. **Card inclusion:** Every task with `worktree` set in the plan, plus all independent worktrees (see Independent Worktree Cards above). Include `done` tasks from the current session briefly (with `merged` activity) until the worktree is cleaned up.
2. **Sort order:** `active` → `monitoring` → `stopped` → `merged` → independent (monitored: any activity except `no PR`) → independent (`no PR`).
3. **Empty state:** If no plan worktrees exist but independent worktrees exist, still render Worktree Cards (independent only). If no worktrees of any kind exist and a plan is loaded, omit the Worktrees section header — only show Queued.

### Queued section

1. **Card inclusion:**
   - `pending` tasks with all `depends_on` done — show Status as `ready`.
   - `pending` tasks with unmet dependencies and `blocked` tasks — show Status as `blocked on T-{id}`.
   - Omit `cancelled` tasks unless the human asks for a full plan view.
2. **Sort order:** `ready` → `blocked`.
3. **Empty state:** If no queued tasks, omit the section.

### Pending Reviews

1. Render when there are entries in the pending reviews list. Omit entirely when empty.

### No active plan

If no plan is loaded and independent worktrees exist, render Worktree Cards (independent only) followed by:

> No active plan. Give me an assignment to get started.

If no plan is loaded and no independent worktrees exist, display exactly:

> No active plan. Give me an assignment to get started.

### Single worktree

If only one worktree is active, still render its card (do not switch to prose).
