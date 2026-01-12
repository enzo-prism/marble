#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

latest_derived=$(ls -td "${HOME}/Library/Developer/Xcode/DerivedData"/marble-* 2>/dev/null | head -n 1 || true)

if [[ -z "$latest_derived" ]]; then
  echo "No DerivedData found for marble. Run tests first." >&2
  exit 1
fi

echo "DerivedData: ${latest_derived}"

echo "Test Logs: ${latest_derived}/Logs/Test"

if ls "${latest_derived}/Logs/Test"/*.xcresult >/dev/null 2>&1; then
  echo "XCResult Bundles:"
  ls -1 "${latest_derived}/Logs/Test"/*.xcresult
fi

if [[ -d "${ROOT_DIR}/TestResults" ]]; then
  echo "Local TestResults: ${ROOT_DIR}/TestResults"
  if ls "${ROOT_DIR}/TestResults"/*.xcresult >/dev/null 2>&1; then
    echo "Local XCResult Bundles:"
    ls -1 "${ROOT_DIR}/TestResults"/*.xcresult
  fi
fi

echo "Snapshot baselines live next to snapshot tests under Tests/Snapshots/__Snapshots__."
