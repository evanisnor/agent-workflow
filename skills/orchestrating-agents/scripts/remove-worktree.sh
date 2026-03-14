#!/usr/bin/env bash
# remove-worktree.sh — remove a git worktree
# Usage: remove-worktree.sh <worktree-path>
#
# Verifies the path is under WORKTREE_BASE before removing.

set -euo pipefail

WORKTREE_PATH="${1:-}"

if [[ -z "${WORKTREE_PATH}" ]]; then
  echo "Usage: remove-worktree.sh <worktree-path>" >&2
  exit 1
fi

source "${CLAUDE_SKILL_DIR}/../../scripts/config.sh"

# Resolve to absolute paths for comparison
ABS_WORKTREE="$(realpath "${WORKTREE_PATH}" 2>/dev/null || echo "${WORKTREE_PATH}")"
ABS_BASE="$(realpath "${WORKTREE_BASE}" 2>/dev/null || echo "${WORKTREE_BASE}")"

# Safety check: refuse to remove paths outside WORKTREE_BASE
if [[ "${ABS_WORKTREE}" != "${ABS_BASE}/"* ]]; then
  echo "Error: ${WORKTREE_PATH} is not under WORKTREE_BASE (${WORKTREE_BASE}). Refusing to remove." >&2
  exit 1
fi

git worktree remove --force "${ABS_WORKTREE}"
echo "Removed worktree: ${ABS_WORKTREE}"
