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
import time

limit = int(sys.argv[1])
command = sys.argv[2:]
grace = float(os.environ.get("MARBLE_TIMEOUT_GRACE_SECONDS", "15"))
process = subprocess.Popen(command, start_new_session=True)
pgid = process.pid


def group_alive(group_id: int) -> bool:
    try:
        os.killpg(group_id, 0)
    except ProcessLookupError:
        return False
    except OSError:
        return True
    return True


def kill_group(group_id: int, sig: int) -> None:
    try:
        os.killpg(group_id, sig)
    except ProcessLookupError:
        pass


try:
    raise SystemExit(process.wait(timeout=limit))
except subprocess.TimeoutExpired:
    print(
        "ERROR: command exceeded %ss and was killed: %s"
        % (limit, " ".join(command)),
        file=sys.stderr,
    )
    kill_group(pgid, signal.SIGTERM)
    deadline = time.monotonic() + grace
    while group_alive(pgid) and time.monotonic() < deadline:
        time.sleep(0.1)
    # The group leader can exit on SIGTERM while a descendant ignores it and
    # keeps stdout open. process.wait() would then return immediately and skip
    # SIGKILL, leaving tee(1) blocked in release_evidence.sh. Always SIGKILL
    # whoever is still in the session after the grace period.
    kill_group(pgid, signal.SIGKILL)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.wait()
    raise SystemExit(124)
PY
