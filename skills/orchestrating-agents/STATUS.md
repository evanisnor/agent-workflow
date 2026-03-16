---
name: status
description: "Canonical template and rendering rules for the worktree-centric status display."
---

# Agent Status Display

## Trigger Conditions

Render the status display whenever:

- The human asks anything resembling a status query: "what are the agents doing", "status update", "show me agent status", "how is the work going", "what's in progress", etc.
- The `/status` skill is invoked.

Always respond with the tables. Do not summarise in prose instead of or in addition to the tables. Never use bulleted lists, numbered lists, or any non-table format — every piece of status data must appear inside a markdown table row.

## Worktrees Table

```
## Worktrees

| Branch | Task | Agent | Activity | PR |
|--------|------|-------|----------|----|
| `{branch}` | {id}: {title} | {agent} | {activity} | {pr} |
```

**Columns:**

| Column | Source | Notes |
|--------|--------|-------|
| Branch | `task.branch` | Rendered as inline code. This is the worktree's identity. If `task.stacked: true`, append ` (on {parent_branch})`. If the task has stacked dependents, append ` (← T-{child_id})` instead (comma-separated if multiple). |
| Task | `task.id` + `task.title` | Format: `T-{id}: {title}`. Truncate title to 25 chars if needed. |
| Agent | Derived from `TaskGet(agent_id)` + activity classification | See Agent Values below. |
| Activity | Derived from live state | See Activity Values below. |
| PR | `task.pr_url` — render as `#N` linked if available | `—` if none. |

## Agent Values

The Agent column shows the agent's relationship to the worktree:

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
| `independent` | Worktree exists outside any Dispatch plan |

### Stopped-Agent Activity Derivation

When `TaskGet(agent_id)` returns `failed` or `stopped` for a task with `worktree` set:

1. If `task.pr_url` is set and the PR is open (not draft): **`unattended`**
2. Otherwise: **`interrupted`**
3. Verify the worktree path is registered via `git worktree list --porcelain`. If the path is not found, use **`escalation required`** instead.

### Independent Worktree Rows

Worktrees that exist on disk (per `git worktree list --porcelain`) but are not referenced by any plan task's `worktree` field are **independent worktrees**. For each independent worktree (excluding the main worktree):

| Column | Value |
|--------|-------|
| Branch | From `git worktree list --porcelain` (`branch` ref, strip `refs/heads/`). Rendered as inline code. |
| Task | `—` |
| Agent | `—` |
| Activity | `independent` |
| PR | Run `gh pr list --head <branch> --json number,url --jq '.[0]'`. Render `#N` linked if found, `—` if not. |

Independent rows sort **after** all plan rows (after the `merged` group).

## Queued Table

Render this section **below the Worktrees table** when there are tasks without worktrees that should be displayed. If there are no queued tasks, omit the section entirely.

```
## Queued

| Task | Title | Status |
|------|-------|--------|
| {id} | {title} | {status} |
```

**Columns:**

| Column | Source | Notes |
|--------|--------|-------|
| Task | `task.id` | |
| Title | `task.title` | Truncate to 30 chars if needed |
| Status | Derived from dependencies | `ready` if all `depends_on` are `done`; `blocked on T-{id}` otherwise (show the first unmet dependency) |

## Pending Reviews Table

Render this section **below the Queued table** (or below the Worktrees table if Queued is omitted) when there are entries in the pending reviews list. If there are no pending reviews, omit the section entirely.

```
## Pending Reviews

| PR | Title | Author | Status |
|----|-------|--------|--------|
| #N | Title | @author | status |
```

**Columns:**

| Column | Source | Notes |
|--------|--------|-------|
| PR | `pr_number` — render as `#N` linked to `pr_url` | |
| Title | `title` | Truncate to 30 chars if needed |
| Author | `author` — render as `@author` | |
| Status | `status` from pending reviews list | See values below |

**Status values:**

| Value | Meaning |
|-------|---------|
| `preliminary` | Review Agent running; analysis not yet ready |
| `ready` | Analysis complete; awaiting human |
| `reviewing` | Diff pane open; human is actively reviewing |
| `approved` | Human approved; PR left for author to merge |

---

## Rendering Rules

### Worktrees table

1. **Row inclusion:** Every task with `worktree` set in the plan, plus all independent worktrees (see Independent Worktree Rows above). Include `done` tasks from the current session briefly (with `merged` activity) until the worktree is cleaned up.
2. **Sort order:** `active` → `monitoring` → `stopped` → `merged` → `independent`.
3. **Empty state:** If no plan worktrees exist but independent worktrees exist, still render the Worktrees table (with only independent rows). If no worktrees of any kind exist and a plan is loaded, omit the Worktrees section header — only show Queued.

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

If no plan is loaded and independent worktrees exist, render the Worktrees table (independent rows only) followed by:

> No active plan. Give me an assignment to get started.

If no plan is loaded and no independent worktrees exist, display exactly:

> No active plan. Give me an assignment to get started.

### Single worktree

If only one worktree is active, still render the table (do not switch to prose).
