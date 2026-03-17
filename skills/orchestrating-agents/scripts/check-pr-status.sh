#!/usr/bin/env bash
# check-pr-status.sh — single-shot check of PR state and CI/review status
# Usage: check-pr-status.sh <pr-url-or-number>
#
# Outputs only state-change events — never full API response payloads.
# State is persisted in /tmp/dispatch-pr-status-<pr-number>.yaml between invocations.
#
# Exit codes:
#   0 = approved + all CI checks pass
#   1 = changes requested by reviewer
#   2 = CI failure
#   3 = PR closed/merged
#   4 = still in progress (no terminal state reached)
#   5 = reviewer left comments (not formal change request)

set -euo pipefail

PR="${1:-}"
if [[ -z "${PR}" ]]; then
  echo "Usage: check-pr-status.sh <pr-url-or-number>" >&2
  exit 4
fi

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SCRIPT_DIR}/../../../scripts/config.sh"

# Extract PR number for state file naming
PR_NUMBER="$(printf '%s' "${PR}" | grep -oE '[0-9]+$' || echo "${PR}")"
STATE_FILE="/tmp/dispatch-pr-status-${PR_NUMBER}.yaml"

# Initialize state file if absent
if [[ ! -f "${STATE_FILE}" ]]; then
  printf 'last_state: ""\nstate_since: 0\nreviews: []\n' > "${STATE_FILE}"
fi

LAST_STATE="$(yq e '.last_state' "${STATE_FILE}" 2>/dev/null || echo "")"
STATE_SINCE="$(yq e '.state_since' "${STATE_FILE}" 2>/dev/null || echo "0")"
NOW="$(date +%s)"

# Fetch only required fields — never inject full payloads into agent context
RESULT="$(gh pr view "${PR}" \
  --json state,reviewDecision,statusCheckRollup,isDraft,latestReviews \
  2>/dev/null || echo '{"state":"UNKNOWN","reviewDecision":null,"statusCheckRollup":[],"isDraft":false,"latestReviews":[]}')"

STATE="$(printf '%s\n' "${RESULT}" | jq -r '.state')"
REVIEW_DECISION="$(printf '%s\n' "${RESULT}" | jq -r '.reviewDecision // "NONE"')"
IS_DRAFT="$(printf '%s\n' "${RESULT}" | jq -r '.isDraft')"

# Extract per-reviewer review data (login, state, submittedAt)
# Only track CHANGES_REQUESTED, COMMENTED, and APPROVED states
LATEST_REVIEWS_JSON="$(printf '%s\n' "${RESULT}" | jq -c '
  [.latestReviews[]
   | select(.state == "CHANGES_REQUESTED" or .state == "COMMENTED" or .state == "APPROVED")
   | {login: .author.login, state: .state, submitted_at: .submittedAt}]
' 2>/dev/null || echo '[]')"

# Summarise CI checks: count by conclusion, never emit raw log text
# StatusContext objects have .state (not .conclusion/.status), so normalise both types
CI_SUMMARY="$(printf '%s\n' "${RESULT}" | jq -r '
  .statusCheckRollup
  | map(. + {_label: (
      if .conclusion != null then .conclusion
      elif .status != null then .status
      elif .state != null then .state
      else "UNKNOWN"
      end
    )})
  | if length == 0 then "no-checks"
    else
      group_by(._label)
      | map("\(.[0]._label):\(length)")
      | join(" ")
    end
' 2>/dev/null || echo "unknown")"

CI_FAILURES="$(printf '%s\n' "${RESULT}" | jq -r '
  [.statusCheckRollup[] | select(
    .conclusion == "FAILURE" or .conclusion == "TIMED_OUT"
    or .state == "FAILURE" or .state == "ERROR"
  )]
  | length
' 2>/dev/null || echo "0")"

CI_PENDING="$(printf '%s\n' "${RESULT}" | jq -r '
  [.statusCheckRollup[] | select(
    (.conclusion == null and .status != null and .status != "COMPLETED")
    or (.state == "PENDING" or .state == "EXPECTED")
  )]
  | length
' 2>/dev/null || echo "0")"

# Detect new/updated per-reviewer reviews by comparing against state file
NEW_CHANGES_REQUESTED=""
NEW_COMMENTS=""
REVIEW_COUNT="$(printf '%s\n' "${LATEST_REVIEWS_JSON}" | jq -r 'length')"
idx=0
while [[ "${idx}" -lt "${REVIEW_COUNT}" ]]; do
  R_LOGIN="$(printf '%s\n' "${LATEST_REVIEWS_JSON}" | jq -r ".[${idx}].login")"
  R_STATE="$(printf '%s\n' "${LATEST_REVIEWS_JSON}" | jq -r ".[${idx}].state")"
  R_SUBMITTED="$(printf '%s\n' "${LATEST_REVIEWS_JSON}" | jq -r ".[${idx}].submitted_at")"

  # Look up this reviewer in the state file
  SAVED_SUBMITTED="$(yq e ".reviews[] | select(.login == \"${R_LOGIN}\") | .submitted_at" "${STATE_FILE}" 2>/dev/null || echo "")"
  SAVED_REPORTED="$(yq e ".reviews[] | select(.login == \"${R_LOGIN}\") | .reported" "${STATE_FILE}" 2>/dev/null || echo "")"

  IS_NEW="false"
  if [[ -z "${SAVED_SUBMITTED}" ]]; then
    # New reviewer not in state file
    IS_NEW="true"
  elif [[ "${SAVED_SUBMITTED}" != "${R_SUBMITTED}" ]]; then
    # Known reviewer but timestamp changed — new review
    IS_NEW="true"
  elif [[ "${SAVED_REPORTED}" != "true" ]]; then
    # Known reviewer, same timestamp, not yet reported
    IS_NEW="true"
  fi

  if [[ "${IS_NEW}" == "true" ]]; then
    if [[ "${R_STATE}" == "CHANGES_REQUESTED" ]]; then
      NEW_CHANGES_REQUESTED="${NEW_CHANGES_REQUESTED} ${R_LOGIN}"
    elif [[ "${R_STATE}" == "COMMENTED" ]]; then
      NEW_COMMENTS="${NEW_COMMENTS} ${R_LOGIN}"
    fi
  fi

  idx=$(( idx + 1 ))
done
# Trim leading spaces
NEW_CHANGES_REQUESTED="$(printf '%s' "${NEW_CHANGES_REQUESTED}" | sed 's/^ *//')"
NEW_COMMENTS="$(printf '%s' "${NEW_COMMENTS}" | sed 's/^ *//')"

# Compare with last known state
CURRENT_STATE="${STATE}:${REVIEW_DECISION}:${CI_SUMMARY}"

cleanup_state_file() {
  rm -f "${STATE_FILE}"
}

# Write updated state file with full reviews array marked as reported
write_state_file() {
  # Build reviews YAML from current latestReviews
  REVIEWS_YAML="$(printf '%s\n' "${LATEST_REVIEWS_JSON}" | jq -r '
    [.[] | "  - login: \"" + .login + "\"\n    state: \"" + .state + "\"\n    submitted_at: \"" + .submitted_at + "\"\n    reported: true"]
    | join("\n")
  ' 2>/dev/null || echo "")"

  if [[ -n "${REVIEWS_YAML}" ]]; then
    printf 'last_state: "%s"\nstate_since: %s\nreviews:\n%s\n' "${CURRENT_STATE}" "${NOW}" "${REVIEWS_YAML}" > "${STATE_FILE}"
  else
    printf 'last_state: "%s"\nstate_since: %s\nreviews: []\n' "${CURRENT_STATE}" "${NOW}" > "${STATE_FILE}"
  fi
}

if [[ "${CURRENT_STATE}" != "${LAST_STATE}" ]]; then
  echo "State change: state=${STATE} review=${REVIEW_DECISION} ci=${CI_SUMMARY} draft=${IS_DRAFT}"
  write_state_file
else
  # State unchanged — check for timeout
  if [[ "${STATE_SINCE}" -gt 0 ]]; then
    ELAPSED_MINUTES=$(( (NOW - STATE_SINCE) / 60 ))
    TIMEOUT_MINUTES="${POLLING_TIMEOUT_MINUTES:-60}"
    if [[ "${ELAPSED_MINUTES}" -ge "${TIMEOUT_MINUTES}" ]]; then
      echo "TIMEOUT state unchanged for ${ELAPSED_MINUTES} minutes"
    fi
  fi
fi

# Terminal: PR closed/merged (highest priority — always check first)
if [[ "${STATE}" == "MERGED" || "${STATE}" == "CLOSED" ]]; then
  echo "Result: PR ${STATE}"
  cleanup_state_file
  exit 3
fi

# Terminal: approved + all CI pass
if [[ "${REVIEW_DECISION}" == "APPROVED" && "${CI_FAILURES}" == "0" && "${CI_PENDING}" == "0" ]]; then
  echo "Result: approved and CI passing"
  cleanup_state_file
  exit 0
fi

# Changes requested (per-reviewer tracking — only fire for NEW requests)
if [[ -n "${NEW_CHANGES_REQUESTED}" ]]; then
  echo "Result: changes requested by ${NEW_CHANGES_REQUESTED}"
  write_state_file
  exit 1
fi

# CI failure
if [[ "${CI_FAILURES}" -gt 0 ]]; then
  echo "Result: CI failure (${CI_FAILURES} check(s) failed)"
  write_state_file
  exit 2
fi

# Reviewer comments (per-reviewer tracking — only fire for NEW comments)
if [[ -n "${NEW_COMMENTS}" ]]; then
  echo "Result: reviewer comments from ${NEW_COMMENTS}"
  write_state_file
  exit 5
fi

# Still in progress
CI_GREEN="false"
if [[ "${CI_FAILURES}" == "0" && "${CI_PENDING}" == "0" ]]; then
  CI_GREEN="true"
fi
echo "ci_green=${CI_GREEN} review=${REVIEW_DECISION} draft=${IS_DRAFT}"
exit 4
