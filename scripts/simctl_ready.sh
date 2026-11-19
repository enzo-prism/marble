#!/usr/bin/env bash
# Boot a simulator and wait until Ready, with a hard cap on `bootstatus -b`.
# Unbounded bootstatus is how a Shutdown/stuck device can hang CI (N2).
# Default 180s covers a cold parallel-job boot; 44185860768 snapshot died at 120s.
# One extra boot+bootstatus after exit 124: 44203758608 snapshot still died at
# 180s on a fresh UDID while Create used 4m47s of a 5-minute cap.
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "Usage: scripts/simctl_ready.sh <udid> [timeout-seconds]" >&2
  exit 2
fi

udid=$1
timeout_seconds=${2:-${SIMCTL_BOOTSTATUS_TIMEOUT:-180}}

wait_until_ready() {
  xcrun simctl boot "${udid}" >/dev/null 2>&1 || true
  python3 - "${udid}" "${timeout_seconds}" <<'PY'
import subprocess
import sys

udid, timeout = sys.argv[1], int(sys.argv[2])
try:
    completed = subprocess.run(
        ["xcrun", "simctl", "bootstatus", udid, "-b"],
        timeout=timeout,
    )
except subprocess.TimeoutExpired:
    sys.stderr.write(f"simctl bootstatus timed out after {timeout}s for {udid}\n")
    sys.exit(124)
sys.exit(completed.returncode)
PY
}

set +e
wait_until_ready
status=$?
if [[ "${status}" -eq 124 ]]; then
  echo "simctl bootstatus timed out after ${timeout_seconds}s for ${udid}; retrying boot" >&2
  wait_until_ready
  status=$?
fi
set -e
exit "${status}"
