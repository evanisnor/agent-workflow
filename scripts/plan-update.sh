#!/usr/bin/env bash
# plan-update.sh <plan-file> <task-id> <field> <value>
#
# Centralized plan mutation with mandatory read-back validation.
# Applies a single-field update to a task in a plan YAML file and verifies
# the write took effect.
#
# Does NOT handle locking — callers still follow the write-with-lock pattern
# from PLAN_STORAGE.md.
#
# Exit codes:
#   0 — verified (stdout: "OK: <field>=<actual-value>")
#   1 — update failed (task not found or value mismatch)
#   2 — structure error (could not discover tasks path)

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: plan-update.sh <plan-file> <task-id> <field> <value>" >&2
  exit 1
fi

PLAN_FILE="$1"
TASK_ID="$2"
FIELD="$3"
VALUE="$4"

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Discover TASKS_PATH
TASKS_PATH=$("${_SCRIPT_DIR}/discover-tasks-path.sh" "$PLAN_FILE")
discover_exit=$?
if [[ $discover_exit -ne 0 ]]; then
  echo "plan-update.sh: could not discover tasks path (exit $discover_exit)" >&2
  exit 2
fi

# Verify the task exists before attempting the update
EXISTING=$(yq e "($TASKS_PATH[] | select(.id == \"$TASK_ID\")).id" "$PLAN_FILE" 2>/dev/null || true)
if [[ -z "$EXISTING" || "$EXISTING" == "null" ]]; then
  echo "plan-update.sh: task '$TASK_ID' not found in $PLAN_FILE (tasks path: $TASKS_PATH)" >&2
  exit 1
fi

# Apply the update
yq e -i "($TASKS_PATH[] | select(.id == \"$TASK_ID\")).$FIELD = \"$VALUE\"" "$PLAN_FILE"

# Read back and verify
ACTUAL=$(yq e "($TASKS_PATH[] | select(.id == \"$TASK_ID\")).$FIELD" "$PLAN_FILE" 2>/dev/null || true)

if [[ "$ACTUAL" != "$VALUE" ]]; then
  echo "plan-update.sh: read-back mismatch for task '$TASK_ID' field '$FIELD': expected '$VALUE', got '$ACTUAL'" >&2
  exit 1
fi

echo "OK: $FIELD=$ACTUAL"
