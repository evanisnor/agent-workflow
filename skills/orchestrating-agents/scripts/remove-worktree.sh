#!/usr/bin/env bash
# remove-worktree.sh — remove a git worktree
# Usage: remove-worktree.sh <worktree-path>
#
# Safety check: verifies the path is a registered git worktree before removing.

set -euo pipefail

WORKTREE_PATH="${1:-}"

if [[ -z "${WORKTREE_PATH}" ]]; then
  echo "Usage: remove-worktree.sh <worktree-path>" >&2
  exit 1
fi

ABS_WORKTREE="$(realpath "${WORKTREE_PATH}" 2>/dev/null || echo "${WORKTREE_PATH}")"

# Locate the main repo via the worktree's shared git dir
GIT_COMMON_DIR="$(git -C "${ABS_WORKTREE}" rev-parse --git-common-dir 2>/dev/null)" || {
  echo "Error: ${WORKTREE_PATH} does not appear to be a git repository." >&2
  exit 1
}
MAIN_REPO="$(dirname "${GIT_COMMON_DIR}")"

# Safety check: refuse to remove anything not registered as a worktree
if ! git -C "${MAIN_REPO}" worktree list --porcelain | grep -qF "worktree ${ABS_WORKTREE}"; then
  echo "Error: ${WORKTREE_PATH} is not a registered git worktree. Refusing to remove." >&2
  exit 1
fi

git -C "${MAIN_REPO}" worktree remove --force "${ABS_WORKTREE}"
echo "Removed worktree: ${ABS_WORKTREE}"
