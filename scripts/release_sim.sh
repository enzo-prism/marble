#!/usr/bin/env bash
# Create or delete one dedicated iOS Simulator for a Release checks job.
# Never looks up the shared "iPhone 17" by name. Never `shutdown all`.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DEVICE_TYPE="${MARBLE_SIMULATOR_DEVICE_TYPE:-iPhone 17}"
RUNTIME="${MARBLE_SIMULATOR_RUNTIME:-com.apple.CoreSimulator.SimRuntime.iOS-27-0}"

usage() {
  echo "Usage: scripts/release_sim.sh create <name> | delete [udid]" >&2
  exit 2
}

publish_env() {
  local key="$1"
  local value="$2"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "${key}=${value}" >>"${GITHUB_ENV}"
  fi
}

cmd_create() {
  local name="${1:-}"
  local udid=""
  [[ -n "${name}" ]] || usage
  if [[ "${name}" != marble-* ]]; then
    echo "Simulator name must start with marble-: ${name}" >&2
    exit 2
  fi

  # A rerun on the same host can leave the previous named device behind.
  # simctl delete rejects Booted devices, so shut it down first.
  xcrun simctl shutdown "${name}" >/dev/null 2>&1 || true
  xcrun simctl delete "${name}" >/dev/null 2>&1 || true

  udid=$(xcrun simctl create "${name}" "${DEVICE_TYPE}" "${RUNTIME}")
  udid=${udid//$'\n'/}
  if [[ -z "${udid}" ]]; then
    echo "simctl create produced no UDID for ${name}" >&2
    exit 1
  fi

  publish_env MARBLE_SIMULATOR_ID "${udid}"
  publish_env SIMULATOR_UDID "${udid}"
  publish_env MARBLE_SIMULATOR_NAME "${name}"
  "${ROOT_DIR}/scripts/simctl_ready.sh" "${udid}"
  echo "Dedicated simulator ${name} ${udid}"
}

cmd_delete() {
  local udid="${1:-${MARBLE_SIMULATOR_ID:-${SIMULATOR_UDID:-}}}"
  local name="${MARBLE_SIMULATOR_NAME:-}"
  if [[ -n "${udid}" ]]; then
    xcrun simctl shutdown "${udid}" >/dev/null 2>&1 || true
    xcrun simctl delete "${udid}" >/dev/null 2>&1 || true
    echo "Deleted simulator ${udid}"
  elif [[ -n "${name}" ]]; then
    xcrun simctl shutdown "${name}" >/dev/null 2>&1 || true
    xcrun simctl delete "${name}" >/dev/null 2>&1 || true
    echo "Deleted simulator ${name}"
  else
    echo "No MARBLE_SIMULATOR_ID to delete."
  fi
}

case "${1:-}" in
  create)
    shift
    cmd_create "${1:-}"
    ;;
  delete)
    shift
    cmd_delete "${1:-}"
    ;;
  *)
    usage
    ;;
esac
