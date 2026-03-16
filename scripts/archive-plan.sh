#!/usr/bin/env bash
# archive-plan.sh — move a plan YAML to the archived/ subdirectory in plan storage
# Usage: archive-plan.sh <plan-file-path>
#   plan-file-path: path relative to PLAN_REPO (e.g. plans/EPIC-123.yaml)

set -euo pipefail

PLAN_FILE="${1:-}"
if [[ -z "${PLAN_FILE}" ]]; then
  echo "Usage: archive-plan.sh <plan-file-path>" >&2
  exit 1
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

FULL_PATH="${PLAN_REPO}/${PLAN_FILE}"

if [[ ! -f "${FULL_PATH}" ]]; then
  echo "Error: plan file not found: ${FULL_PATH}" >&2
  exit 1
fi

BASENAME="$(basename "${PLAN_FILE}")"
ARCHIVE_DIR="${PLAN_REPO}/archived"
ARCHIVE_PATH="${ARCHIVE_DIR}/${BASENAME}"

mkdir -p "${ARCHIVE_DIR}"

cd "${PLAN_REPO}"

if [[ ! -d ".git" ]]; then
  git init --quiet
fi

git mv "${FULL_PATH}" "${ARCHIVE_PATH}"
git commit -m "archive: ${PLAN_FILE}" --quiet

if _has_remote; then
  git push origin main --quiet
fi

echo "Plan archived: ${ARCHIVE_PATH}"
