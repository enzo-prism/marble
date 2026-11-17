#!/usr/bin/env bash
# Boot a simulator and wait until Ready, with a hard cap on `bootstatus -b`.
# Unbounded bootstatus is how a Shutdown/stuck device can hang CI (N2).
# Default 180s covers a cold parallel-job boot; 44185860768 snapshot died at 120s.
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "Usage: scripts/simctl_ready.sh <udid> [timeout-seconds]" >&2
  exit 2
fi

udid=$1
timeout_seconds=${2:-${SIMCTL_BOOTSTATUS_TIMEOUT:-180}}

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
