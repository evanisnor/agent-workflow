#!/usr/bin/env bash
# schedule-wait.sh <ISO-8601-datetime | now>
#
# If the argument is "now" or resolves to a past time, exits 0 immediately.
# Otherwise prints a human-readable status line and runs caffeinate -t <seconds>
# to hold the process until the target time, then exits 0.

set -euo pipefail

TARGET="${1:-now}"

if [[ "$TARGET" == "now" ]]; then
  exit 0
fi

NOW_EPOCH=$(date +%s)
TARGET_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${TARGET%%[+-]*}" +%s 2>/dev/null \
  || date -d "$TARGET" +%s 2>/dev/null \
  || { echo "schedule-wait.sh: cannot parse datetime: '$TARGET' (expected ISO 8601, e.g. 2026-03-15T09:00:00)" >&2; exit 1; })

DELTA=$(( TARGET_EPOCH - NOW_EPOCH ))

if [[ $DELTA -le 0 ]]; then
  exit 0
fi

HOURS=$(( DELTA / 3600 ))
MINUTES=$(( (DELTA % 3600) / 60 ))

if [[ $HOURS -gt 0 ]]; then
  HUMAN="${HOURS}h ${MINUTES}m"
else
  HUMAN="${MINUTES}m"
fi

echo "Waiting until $TARGET — approximately $HUMAN"
caffeinate -t "$DELTA"
