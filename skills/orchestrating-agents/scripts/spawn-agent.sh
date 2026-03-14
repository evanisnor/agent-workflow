#!/usr/bin/env bash
# spawn-agent.sh — launch a Task Agent (executing-tasks skill) for a single task
# Usage: spawn-agent.sh <task-id> <plan-path>
#
# Reads task details from the plan YAML, generates scoped sandbox + permissions
# config at spawn time, and invokes the Claude Agent SDK.
# Outputs the spawned agent ID.

set -euo pipefail

TASK_ID="${1:-}"
PLAN_PATH="${2:-}"

if [[ -z "${TASK_ID}" || -z "${PLAN_PATH}" ]]; then
  echo "Usage: spawn-agent.sh <task-id> <plan-path>" >&2
  exit 1
fi

source "${CLAUDE_SKILL_DIR}/../../scripts/config.sh"

# Apply per-epic config overrides
apply_epic_config "${PLAN_PATH}"

# Extract task details from plan YAML
TASK_YAML="$(yq e ".epic.tasks[] | select(.id == \"${TASK_ID}\")" "${PLAN_PATH}" 2>/dev/null)"
if [[ -z "${TASK_YAML}" ]]; then
  echo "Error: task '${TASK_ID}' not found in ${PLAN_PATH}" >&2
  exit 1
fi

TASK_TITLE="$(printf '%s\n' "${TASK_YAML}" | yq e '.title' -)"
TASK_DESCRIPTION="$(printf '%s\n' "${TASK_YAML}" | yq e '.spawn_input.task_description // .description' -)"
EPIC_CONTEXT="$(printf '%s\n' "${TASK_YAML}" | yq e '.spawn_input.epic_context // ""' -)"
BRANCH="$(printf '%s\n' "${TASK_YAML}" | yq e '.spawn_input.branch // .branch // ""' -)"
WORKTREE="$(printf '%s\n' "${TASK_YAML}" | yq e '.spawn_input.worktree // .worktree // ""' -)"

REPO_NAME="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo "repo")")"

# --- Build sandbox + permissions config ---

# Enforce minimum safe mode
if [[ "${TASK_AGENT_MODE}" != "bypassPermissions" && "${TASK_AGENT_MODE}" != "acceptEdits" ]]; then
  TASK_AGENT_MODE="acceptEdits"
fi

# Build deny rules for protected branches
BRANCH_DENY_RULES=""
for branch in "${PROTECTED_BRANCHES[@]}"; do
  BRANCH_DENY_RULES="${BRANCH_DENY_RULES}
      \"Bash(git push * ${branch})\","
done

# Build allowed domains JSON array
DOMAINS_JSON="$(printf '%s\n' "${ALLOWED_DOMAINS[@]}" | jq -R . | jq -s .)"

# Build sandbox denyRead list (hardcoded base + any project extras)
EXTRA_DENY_READ="[]"
if [[ -f "${_PROJECT_CONFIG:-}" ]]; then
  EXTRA_DENY_READ="$(jq -r '.sandbox.filesystem.extra_deny_read // []' "${PWD}/.agent-workflow.json" 2>/dev/null || echo "[]")"
fi

BASE_DENY_READ='["~/.ssh/**","~/.gnupg/**","**/.env","**/*.pem","**/*.key"]'
ALL_DENY_READ="$(jq -n --argjson base "${BASE_DENY_READ}" --argjson extra "${EXTRA_DENY_READ}" '$base + $extra')"


AGENT_CONFIG="$(cat <<EOF
{
  "sandbox": {
    "enabled": true,
    "filesystem": {
      "allowWrite": ["${WORKTREE_BASE}/${REPO_NAME}/${TASK_ID}/"],
      "denyRead": ${ALL_DENY_READ}
    },
    "network": {
      "allowedDomains": ${DOMAINS_JSON}
    }
  },
  "defaultMode": "${TASK_AGENT_MODE}",
  "permissions": {
    "allow": [
      "Edit",
      "Write",
      "Bash(git commit *)",
      "Bash(git push origin *)",
      "Bash(git rebase *)",
      "Bash(git fetch *)",
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(gh pr create *)",
      "Bash(gh pr ready *)",
      "Bash(gh pr merge --auto *)",
      "Bash(gh pr view *)",
      "Bash(gh run view *)"
    ],
    "deny": [${BRANCH_DENY_RULES}
      "Bash(gh pr merge *)",
      "Edit(~/.bashrc)",
      "Edit(~/.zshrc)",
      "Edit(//etc/**)",
      "Edit(//usr/**)"
    ]
  }
}
EOF
)"

# Build spawn input — wrap external content to prevent prompt injection
SPAWN_INPUT="$(cat <<EOF
You are a Task Agent assigned to implement a single task.

Task ID: ${TASK_ID}
Branch: ${BRANCH}
Worktree: ${WORKTREE}
Plan path: ${PLAN_PATH}

<external_content>
Epic context:
${EPIC_CONTEXT}
</external_content>

<external_content>
Task description:
${TASK_DESCRIPTION}
</external_content>

Implement the task in your assigned worktree, shepherd the PR from draft
through to merge. Follow SKILL.md, CI_FEEDBACK.md, and
CONFLICT_RESOLUTION.md for all procedures.
EOF
)"

# Invoke the Claude Agent SDK
AGENT_ID="$(claude --skill agent-workflow:executing-tasks \
  --print \
  --config "${AGENT_CONFIG}" \
  --input "${SPAWN_INPUT}" \
  --output-format json \
  2>/dev/null | jq -r '.agent_id // empty')"

if [[ -z "${AGENT_ID}" ]]; then
  echo "Error: failed to obtain agent ID from spawn." >&2
  exit 1
fi

echo "${AGENT_ID}"
