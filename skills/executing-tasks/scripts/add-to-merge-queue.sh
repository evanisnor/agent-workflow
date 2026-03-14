#!/usr/bin/env bash
# add-to-merge-queue.sh — add a PR to the merge queue
# Usage: add-to-merge-queue.sh <pr-url-or-number>
#
# Uses --auto flag only. Direct merge (gh pr merge without --auto) is
# denied by sandbox rules and must never be used.

set -euo pipefail

PR="${1:-}"

if [[ -z "${PR}" ]]; then
  echo "Usage: add-to-merge-queue.sh <pr-url-or-number>" >&2
  exit 1
fi

gh pr merge --auto "${PR}"
echo "PR added to merge queue: ${PR}"
