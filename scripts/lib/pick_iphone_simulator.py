#!/usr/bin/env python3
"""Pick a deterministic iPhone simulator for Marble's CI and local test scripts.

GitHub's macos-26 image has no iPhone 15 Pro. The previous fallback sorted
available iPhones by name descending, so "iPhone Air" beat "iPhone 17 Pro".
Air is a different geometry than the Pro devices the UI suite was written for.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys

UI_PREFERRED_NAMES = (
    "iPhone 17 Pro",
    "iPhone 16 Pro",
    "iPhone 15 Pro",
    "iPhone 17",
    "iPhone 16",
    "iPhone 15",
)

# History native chrome is recorded against a 15 Pro-class window scene.
# Current macos-26 iPhone 17 Pro scenes ghost navigation titles in that harness.
SNAPSHOT_PREFERRED_NAMES = (
    "iPhone 15 Pro",
    "iPhone 16 Pro",
    "iPhone Air",
    "iPhone 17 Pro",
    "iPhone 17",
    "iPhone 16",
    "iPhone 15",
)

AVOID_SUBSTRINGS = (
    " air",
    " mini",
    " se",
    " plus",
)


def runtime_version(key: str) -> tuple[int, ...]:
    match = re.search(r"iOS-([0-9\-]+)", key)
    if not match:
        return (0,)
    return tuple(int(part) for part in match.group(1).split("-") if part.isdigit())


def is_available(device: dict) -> bool:
    if device.get("isAvailable") is True:
        return True
    if device.get("availability") == "(available)":
        return True
    return device.get("availabilityError") is None


def preference_rank(name: str, profile: str) -> int:
    lowered = name.strip().lower()
    preferred_names = SNAPSHOT_PREFERRED_NAMES if profile == "snapshot" else UI_PREFERRED_NAMES
    for index, preferred in enumerate(preferred_names):
        if lowered == preferred.lower():
            return index
    if profile != "snapshot" and any(token in lowered for token in AVOID_SUBSTRINGS):
        return 1000
    if lowered.endswith("e") and "pro" not in lowered:
        return 900
    if "pro max" in lowered:
        return 50
    if "pro" in lowered:
        return 10
    return 100


def collect_iphones(
    data: dict, runtime: str, profile: str
) -> list[tuple[tuple[int, ...], int, str, str]]:
    candidates: list[tuple[tuple[int, ...], int, str, str]] = []
    for device in data.get("devices", {}).get(runtime, []):
        if not is_available(device):
            continue
        name = device.get("name", "")
        if not name.startswith("iPhone"):
            continue
        udid = device.get("udid") or ""
        if not udid:
            continue
        candidates.append((runtime_version(runtime), preference_rank(name, profile), name, udid))
    return candidates


def pick_udid(data: dict, preferred_name: str, required_runtime: str, profile: str) -> str:
    runtimes = list(data.get("devices", {}))
    search_order = [required_runtime] + sorted(
        (runtime for runtime in runtimes if runtime != required_runtime and "iOS-" in runtime),
        key=runtime_version,
        reverse=True,
    )
    preferred = preferred_name.strip().lower()
    for runtime in search_order:
        candidates = collect_iphones(data, runtime, profile)
        if not candidates:
            continue
        for _version, _rank, name, udid in candidates:
            if name.lower() == preferred:
                return udid
        candidates.sort(key=lambda item: (item[1], item[2]))
        return candidates[0][3]
    return ""


def load_devices(path: str | None) -> dict:
    if path:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "-j"])
    return json.loads(raw)


def main(argv: list[str]) -> int:
    preferred = os.environ.get("MARBLE_SIMULATOR_NAME", "iPhone 17 Pro")
    runtime = os.environ.get(
        "MARBLE_SIMULATOR_RUNTIME", "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
    )
    profile = os.environ.get("MARBLE_SIMULATOR_PROFILE", "ui")
    devices_json = None
    args = argv[1:]
    while args:
        if args[0] == "--preferred" and len(args) >= 2:
            preferred = args[1]
            args = args[2:]
        elif args[0] == "--runtime" and len(args) >= 2:
            runtime = args[1]
            args = args[2:]
        elif args[0] == "--profile" and len(args) >= 2:
            profile = args[1]
            args = args[2:]
        elif args[0] == "--devices-json" and len(args) >= 2:
            devices_json = args[1]
            args = args[2:]
        else:
            print(f"Unknown argument: {args[0]}", file=sys.stderr)
            return 2
    if profile == "snapshot" and preferred == "iPhone 17 Pro":
        preferred = "iPhone 15 Pro"
    data = load_devices(devices_json)
    sys.stdout.write(pick_udid(data, preferred, runtime, profile))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
