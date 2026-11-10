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
        # Darwin reports a just-exited leader as EPERM until it is reaped.
        return process.poll() is None
    return True


def kill_group(group_id: int, sig: int) -> None:
    try:
        os.killpg(group_id, sig)
    except OSError:
        pass
    try:
        os.kill(group_id, sig)
    except OSError:
        pass


try:
    raise SystemExit(process.wait(timeout=limit))
except subprocess.TimeoutExpired:
    print(
        "ERROR: command exceeded %ss and was killed: %s"
        % (limit, " ".join(command)),
        file=sys.stderr,
    )
    try:
        kill_group(pgid, signal.SIGTERM)
        deadline = time.monotonic() + grace
        while group_alive(pgid) and time.monotonic() < deadline:
            time.sleep(0.1)
        # Always SIGKILL remaining session members. The group leader can exit
        # on SIGTERM while a descendant keeps stdout open; waiting only on the
        # leader would then skip SIGKILL and block tee(1) in release_evidence.sh.
        # Darwin can also raise EPERM on a zombie leader — never let that
        # escape as exit 1 instead of 124.
        kill_group(pgid, signal.SIGKILL)
        try:
            process.kill()
        except OSError:
            pass
        try:
            process.wait(timeout=5)
        except Exception:
            pass
    except Exception as exc:
        print("watchdog kill failed: %s" % exc, file=sys.stderr)
    raise SystemExit(124)
PY
