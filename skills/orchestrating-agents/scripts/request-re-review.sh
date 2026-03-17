#!/usr/bin/env bash
# request-re-review.sh — re-request a reviewer's review on a PR
# Usage: request-re-review.sh <pr-url-or-number> <reviewer-username>
#
# Checks if the reviewer has already APPROVED. If so, skips.
# Otherwise, adds them as a reviewer to trigger a re-review notification.
#
# Exit codes:
#   0 = success (re-review requested or skipped because already approved)
#   1 = error

set -euo pipefail

PR="${1:-}"
REVIEWER="${2:-}"

if [[ -z "${PR}" || -z "${REVIEWER}" ]]; then
  echo "Usage: request-re-review.sh <pr-url-or-number> <reviewer-username>" >&2
  exit 1
fi

# Check if reviewer already approved
REVIEWER_STATE="$(gh pr view "${PR}" --json latestReviews \
  --jq ".latestReviews[] | select(.author.login == \"${REVIEWER}\") | .state" \
  2>/dev/null || echo "")"

if [[ "${REVIEWER_STATE}" == "APPROVED" ]]; then
  echo "Skipped: ${REVIEWER} has already approved"
  exit 0
fi

# Re-request review
if gh pr edit "${PR}" --add-reviewer "${REVIEWER}" 2>/dev/null; then
  echo "Re-review requested from ${REVIEWER}"
  exit 0
else
  echo "Error: failed to request re-review from ${REVIEWER}" >&2
  exit 1
fi
