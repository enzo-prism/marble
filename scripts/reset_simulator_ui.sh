#!/usr/bin/env bash
# Force the dedicated simulator back to default Dynamic Type.
#
# WorkoutHistory snapshots must change the *device* content size because UIKit
# search fields cache the process-wide category. That setting persists across
# simctl shutdown/boot on current macos-26 images. If it leaks, later snapshot
# groups, UI tests, and accessibility audits run at XXXL and fail as if the
# product layout had regressed.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
desired="${1:-large}"
simulator_id="${MARBLE_SIMULATOR_ID:-${SIMULATOR_UDID:-}}"

if [[ -z "${simulator_id}" ]]; then
  destination=$("${ROOT_DIR}/scripts/sim_destination.sh") || exit 0
  if [[ "${destination}" == id=* ]]; then
    simulator_id="${destination#id=}"
  fi
fi

if [[ -z "${simulator_id}" ]]; then
  echo "No simulator id; skipping content size reset." >&2
  exit 0
fi

xcrun simctl boot "${simulator_id}" >/dev/null 2>&1 || true
xcrun simctl bootstatus "${simulator_id}" -b >/dev/null 2>&1 || true

current=""
for _ in 1 2 3 4 5 6; do
  if xcrun simctl ui "${simulator_id}" content_size "${desired}" >/dev/null 2>&1; then
    current=$(xcrun simctl ui "${simulator_id}" content_size 2>/dev/null | tr -d '[:space:]' || true)
    if [[ "${current}" == "${desired}" ]]; then
      echo "Simulator ${simulator_id} content_size=${current}"
      exit 0
    fi
  fi
  sleep 1
done

echo "Failed to set simulator content_size to '${desired}' (now '${current}')." >&2
exit 1
