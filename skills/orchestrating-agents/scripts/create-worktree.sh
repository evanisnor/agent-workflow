#!/usr/bin/env bash
# create-worktree.sh — create a git worktree for a task
# Usage: create-worktree.sh <repo-path> <task-id> <branch-name>
#
# Outputs the created worktree path on success.
# Does NOT copy .env files, credential files, or SSH keys.

set -euo pipefail

REPO_PATH="${1:-}"
TASK_ID="${2:-}"
BRANCH="${3:-}"

if [[ -z "${REPO_PATH}" || -z "${TASK_ID}" || -z "${BRANCH}" ]]; then
  echo "Usage: create-worktree.sh <repo-path> <task-id> <branch-name>" >&2
  exit 1
fi

source "${CLAUDE_SKILL_DIR}/../../scripts/config.sh"

REPO_NAME="$(basename "${REPO_PATH}")"
WORKTREE_PATH="${WORKTREE_BASE}/${REPO_NAME}/${TASK_ID}"

# Create the worktree
cd "${REPO_PATH}"
git worktree add "${WORKTREE_PATH}" -b "${BRANCH}"

# Safety: ensure no sensitive files were inadvertently linked or copied
# git worktree shares the .git dir; it does not copy working tree files,
# but we explicitly remove any sensitive files if they exist.
for pattern in ".env" "*.pem" "*.key" ".env.*"; do
  find "${WORKTREE_PATH}" -maxdepth 3 -name "${pattern}" -not -path "*/.git/*" -delete 2>/dev/null || true
done

echo "${WORKTREE_PATH}"
