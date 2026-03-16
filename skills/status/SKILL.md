---
name: status
description: "Display a status table of all active worktrees, their agent state, current activity, and PR state. Invoke with /status."
---

Render the status display immediately using the rules below. Do not read any external files. Do not summarise in prose instead of or in addition to the tables.

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
| Branch | `task.branch` | Rendered as inline code. If stacked, append ` (on {parent_branch})`. If it has stacked dependents, append ` (← T-{child_id})`. |
| Task | `task.id` + `task.title` | Format: `T-{id}: {title}`. Truncate title to 25 chars if needed. |
| Agent | Last-known agent liveness | See Agent Values below. |
| Activity | Last-known activity state | See Activity Values below. |
| PR | `task.pr_url` — render as `#N` linked if available | `—` if none. |

**Note:** Agent and Activity values reflect the Orchestrating Agent's last-known state. If agent liveness has not been checked recently, values may be stale. The canonical status rendering (STATUS.md) performs live liveness checks.

## Agent Values

| Value | When to use |
|-------|-------------|
| `active` | Agent is running and doing active work: `implementing`, `pre-PR checklist`, `awaiting diff review`, `fixing CI (N/M)`, `stacked — implementing` |
| `monitoring` | Agent is running but in a passive-wait state: `CI running`, `awaiting review`, `changes requested`, `in merge queue`, `stacking offered` |
| `stopped` | Agent is known to have failed or stopped |

## Activity Values

| Activity | When to use |
|----------|-------------|
| `implementing` | No PR open yet, agent writing code |
| `pre-PR checklist` | Task Agent has signalled checklist underway |
| `awaiting diff review` | Task Agent has requested diff approval from human |
| `stacking offered` | Diff approved; human deciding about stacking |
| `stacked — implementing` | Task is stacked; agent actively implementing |
| `CI running` | PR open, CI checks in progress |
| `fixing CI (N/M)` | Agent applying CI fix; N = current attempt, M = max |
| `awaiting review` | PR marked ready, no review decision yet |
| `changes requested` | Reviewer requested changes |
| `in merge queue` | PR approved and added to merge queue |
| `merged` | PR merged successfully |
| `interrupted` | Agent stopped; work was incomplete (no PR or PR is draft) |
| `unattended` | Agent stopped; PR is open and in flight |
| `escalation required` | CI fix limit exceeded or unrecoverable error |
| `independent` | Worktree exists outside any Dispatch plan |

## Queued Table

Render below the Worktrees table when there are tasks without worktrees. Omit if no queued tasks exist.

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
| Status | Derived from dependencies | `ready` if all `depends_on` are `done`; `blocked on T-{id}` otherwise |

**Independent worktrees:** Worktrees from `git worktree list` that are not referenced by any plan task (excluding the main worktree) appear in the Worktrees table with Task `—`, Agent `—`, Activity `independent`, and PR discovered via `gh pr list --head <branch>`. See STATUS.md § Independent Worktree Rows for full column definitions.

## Rendering Rules

1. **Worktrees table row inclusion:** Every task with a worktree, plus all independent worktrees. Include recently merged tasks until cleanup. Sort: `active` → `monitoring` → `stopped` → `merged` → `independent`.

2. **Queued section row inclusion:** `pending` tasks with all deps met (show as `ready`). `pending`/`blocked` tasks with unmet deps (show as `blocked on T-{id}`). Omit `cancelled` unless human asks for full view. Sort: `ready` → `blocked`.

3. **Empty states:** If no plan worktrees exist but independent worktrees exist, still render the Worktrees table (independent rows only). If no worktrees of any kind exist and a plan is loaded, omit Worktrees header — show only Queued. If no queued tasks, omit the section.

4. **No active plan:** If independent worktrees exist, render the Worktrees table (independent rows only) above the no-plan text. Then display:
   > No active plan. Here's what you can do:
   > - **Plan** — describe what you'd like to build and I'll decompose it into tasks
   > - **Implement** — point me at an existing plan file to start executing
   >
   > Also available: `/status`, `/config`, `/help`

5. **Single worktree:** still render the table (do not switch to prose).
