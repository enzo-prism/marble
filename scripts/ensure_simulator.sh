#!/usr/bin/env bash
# Boot a concrete iPhone simulator and fail fast if CoreSimulator has none.
#
# macos-26 images can drop every xcodebuild destination after `simctl shutdown`
# (CI 43032442125: History a11y reboot, then Composer listed only Mac /
# placeholder devices). Wait for the pinned UDID to return before re-picking.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
wait_seconds="${MARBLE_SIMULATOR_WAIT_SECONDS:-45}"
deadline=$((SECONDS + wait_seconds))
pinned_id="${MARBLE_SIMULATOR_ID:-}"

simctl() {
  xcrun simctl "$@"
}

pick_id() {
  if [[ -n "${MARBLE_SIMULATOR_ID:-}" ]]; then
    printf '%s\n' "${MARBLE_SIMULATOR_ID}"
    return 0
  fi
  local destination
  if ! destination=$("${ROOT_DIR}/scripts/sim_destination.sh"); then
    return 1
  fi
  if [[ "${destination}" != id=* ]]; then
    return 1
  fi
  printf '%s\n' "${destination#id=}"
}

device_state() {
  local udid="$1"
  simctl list devices -j 2>/dev/null | python3 -c '
import json
import sys

udid = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    print("error")
    raise SystemExit(0)

for devices in data.get("devices", {}).values():
    for device in devices:
        if device.get("udid") != udid:
            continue
        if device.get("isAvailable") is False:
            print("unavailable")
            raise SystemExit(0)
        print("available")
        raise SystemExit(0)
print("missing")
' "${udid}" || printf 'error\n'
}

while (( SECONDS < deadline )); do
  if ! id=$(pick_id); then
    sleep 2
    continue
  fi
  state=$(device_state "${id}" || printf 'error\n')
  case "${state}" in
    available)
      simctl boot "${id}" >/dev/null 2>&1 || true
      if simctl bootstatus "${id}" -b >/dev/null 2>&1; then
        printf 'id=%s\n' "${id}"
        exit 0
      fi
      ;;
    missing|unavailable)
      # Keep a pinned UDID while CoreSimulatorService recovers so later
      # snapshot groups stay on the same scene instead of jumping devices.
      if [[ -z "${pinned_id}" || "${id}" != "${pinned_id}" ]]; then
        unset MARBLE_SIMULATOR_ID
      fi
      ;;
    error)
      ;;
  esac
  sleep 2
done

echo "No iPhone simulator became available for xcodebuild within ${wait_seconds}s." >&2
if [[ -n "${pinned_id}" ]]; then
  echo "Pinned simulator ${pinned_id} was missing from CoreSimulator." >&2
fi
simctl list devices >&2 || true
exit 1
