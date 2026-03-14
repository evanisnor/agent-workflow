#!/usr/bin/env bash
# spawn-planning-agent.sh — launch the planning-tasks skill as a subprocess
# Usage: spawn-planning-agent.sh <plan-storage-path> <assignment-description>
#
# Waits for the agent to return a finalized plan path and prints it.

set -euo pipefail

PLAN_STORAGE_PATH="${1:-}"
ASSIGNMENT="${2:-}"

if [[ -z "${PLAN_STORAGE_PATH}" || -z "${ASSIGNMENT}" ]]; then
  echo "Usage: spawn-planning-agent.sh <plan-storage-path> <assignment-description>" >&2
  exit 1
fi

source "${CLAUDE_SKILL_DIR}/../../scripts/config.sh"

# Build structured context for the Planning Agent
# Assignment description is external input — wrap in tags to prevent injection
SPAWN_INPUT="$(cat <<EOF
You are being spawned as a Planning Agent to decompose a new piece of work.

Plan storage path: ${PLAN_STORAGE_PATH}

<external_content>
Assignment:
${ASSIGNMENT}
</external_content>

Decompose the assignment into atomic tasks, build a dependency tree, and save
the finalized plan to the plan storage path. Return the finalized plan file
path when complete, then exit.
EOF
)"

# Invoke the Claude Agent SDK to launch the planning-tasks skill
AGENT_OUTPUT="$(claude --skill agent-workflow:planning-tasks \
  --print \
  --input "${SPAWN_INPUT}" \
  2>&1)"

# Extract the plan file path from agent output (last line that looks like a path)
PLAN_PATH="$(printf '%s\n' "${AGENT_OUTPUT}" | grep -E '^\S+\.yaml$' | tail -1 || true)"

if [[ -z "${PLAN_PATH}" ]]; then
  echo "Error: Planning Agent did not return a plan file path." >&2
  echo "Agent output:" >&2
  echo "${AGENT_OUTPUT}" >&2
  exit 1
fi

echo "${PLAN_PATH}"
