#!/usr/bin/env bash
# close-review-pane.sh — close a tmux review window
# Usage: close-review-pane.sh <window-id>

set -euo pipefail

WINDOW_ID="${1:-}"

if [[ -z "${WINDOW_ID}" ]]; then
  echo "Usage: close-review-pane.sh <window-id>" >&2
  exit 1
fi

if [[ -z "${TMUX:-}" ]]; then
  echo "Error: not running inside a tmux session." >&2
  exit 1
fi

tmux kill-window -t "${WINDOW_ID}"
echo "Closed review window: ${WINDOW_ID}"
