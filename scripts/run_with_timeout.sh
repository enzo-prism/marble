#!/usr/bin/env bash
# Run a command with a hard deadline. macOS does not ship GNU timeout(1).
# Usage: scripts/run_with_timeout.sh SECONDS command [args...]
set -euo pipefail

if (($# < 2)); then
  echo "Usage: $0 SECONDS command [args...]" >&2
  exit 2
fi

python3 - "$@" <<'PY'
import os
import signal
import subprocess
import sys

limit = int(sys.argv[1])
command = sys.argv[2:]
process = subprocess.Popen(command, start_new_session=True)
try:
    raise SystemExit(process.wait(timeout=limit))
except subprocess.TimeoutExpired:
    print(
        "ERROR: command exceeded %ss and was killed: %s"
        % (limit, " ".join(command)),
        file=sys.stderr,
    )
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
    raise SystemExit(124)
PY
