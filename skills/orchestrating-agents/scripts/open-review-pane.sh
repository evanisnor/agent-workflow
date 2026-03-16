#!/usr/bin/env bash
# open-review-pane.sh — open a new tmux window showing the branch diff for review
# Usage: open-review-pane.sh <window-name> <worktree-path> [mode]
#
# mode: "split" (delta --side-by-side) or "unified" (delta default).
#       Defaults to $DIFF_MODE from config.sh, then "split".
#       Has no effect when delta is not installed.
#
# Opens a new named window in the current tmux session — never modifies the
# current window layout. Each review gets the full screen.
# Outputs the tmux window ID on success.

set -euo pipefail

WINDOW_NAME="${1:-}"
WORKTREE_PATH="${2:-}"
MODE="${3:-${DIFF_MODE:-split}}"

if [[ -z "${WINDOW_NAME}" || -z "${WORKTREE_PATH}" ]]; then
  echo "Usage: open-review-pane.sh <window-name> <worktree-path> [mode]" >&2
  exit 1
fi

if [[ ! -d "${WORKTREE_PATH}" ]]; then
  echo "Error: worktree path does not exist: ${WORKTREE_PATH}" >&2
  exit 1
fi

# Must be running inside tmux
if [[ -z "${TMUX:-}" ]]; then
  echo "Error: not running inside a tmux session. Cannot open review window." >&2
  exit 1
fi

# Detect the base branch from the remote HEAD pointer; fall back to origin/main
BASE_BRANCH="$(git -C "${WORKTREE_PATH}" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
  | sed 's@^refs/remotes/@@')" || true
BASE_BRANCH="${BASE_BRANCH:-origin/main}"

# Build diff command — use delta when available, respecting the requested mode
if command -v delta &>/dev/null; then
  if [[ "${MODE}" == "split" ]]; then
    DIFF_CMD="git -C \"${WORKTREE_PATH}\" diff \"${BASE_BRANCH}...HEAD\" | delta --side-by-side"
  else
    DIFF_CMD="git -C \"${WORKTREE_PATH}\" diff \"${BASE_BRANCH}...HEAD\" | delta"
  fi
else
  DIFF_CMD="git -C \"${WORKTREE_PATH}\" diff \"${BASE_BRANCH}...HEAD\""
fi

# Open a new named window in the current session
WINDOW_ID="$(tmux new-window -P -F '#{window_id}' -n "${WINDOW_NAME}" \
  "${DIFF_CMD}; printf '\n--- end of diff ---\n'; read -r -p 'When done reviewing, return to Claude and approve or request changes. Press Enter to close this window.' _")"

echo "${WINDOW_ID}"
