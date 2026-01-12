#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${MARBLE_SIMULATOR_ID:-}" ]]; then
  echo "id=${MARBLE_SIMULATOR_ID}"
  exit 0
fi

preferred_name="${MARBLE_SIMULATOR_NAME:-iPhone 15 Pro}"

destination_id=$(python3 - "$preferred_name" <<'PY'
import json
import re
import subprocess
import sys

preferred = sys.argv[1].strip().lower()

raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "-j"])
data = json.loads(raw)

def is_available(device):
    if device.get("isAvailable") is True:
        return True
    availability = device.get("availability", "")
    if availability == "(available)":
        return True
    return device.get("availabilityError") is None

def runtime_version(key):
    match = re.search(r"iOS-([0-9\-]+)", key)
    if not match:
        return (0,)
    parts = match.group(1).split("-")
    return tuple(int(p) for p in parts if p.isdigit())

runtimes = sorted(data.get("devices", {}).keys(), key=runtime_version, reverse=True)

candidates = []
for runtime in runtimes:
    for device in data["devices"].get(runtime, []):
        if not is_available(device):
            continue
        name = device.get("name", "")
        if not name.startswith("iPhone"):
            continue
        candidates.append((runtime_version(runtime), name, device.get("udid", "")))

if not candidates:
    print("")
    sys.exit(0)

candidates.sort(key=lambda item: (item[0], item[1]), reverse=True)

for version, name, udid in candidates:
    if name.lower() == preferred and udid:
        print(udid)
        sys.exit(0)

# Fallback to the newest available iPhone.
print(candidates[0][2])
PY
)

if [[ -z "${destination_id}" ]]; then
  echo "No available iPhone simulator found. Open Xcode > Settings > Platforms to install a simulator runtime." >&2
  exit 1
fi

echo "id=${destination_id}"
