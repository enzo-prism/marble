#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ -n "${MARBLE_SIMULATOR_ID:-}" ]]; then
  echo "id=${MARBLE_SIMULATOR_ID}"
  exit 0
fi

preferred_name="${MARBLE_SIMULATOR_NAME:-iPhone 17 Pro}"
preferred_runtime="${MARBLE_SIMULATOR_RUNTIME:-com.apple.CoreSimulator.SimRuntime.iOS-26-5}"
profile="${MARBLE_SIMULATOR_PROFILE:-ui}"

destination_id=$(
  python3 "${ROOT_DIR}/scripts/lib/pick_iphone_simulator.py" \
    --preferred "${preferred_name}" \
    --runtime "${preferred_runtime}" \
    --profile "${profile}"
)

if [[ -z "${destination_id}" ]]; then
  echo "No available iPhone simulator found. Open Xcode > Settings > Platforms to install a simulator runtime." >&2
  exit 1
fi

echo "id=${destination_id}"
