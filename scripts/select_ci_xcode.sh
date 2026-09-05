#!/usr/bin/env bash
set -euo pipefail
# Update deliberately together with the runtime and snapshot baselines.
expected_version=26.6
expected_build=17F113
path="/Applications/Xcode_${expected_version}.app"
if [[ ! -d "$path" ]]; then path=/Applications/Xcode.app; fi
sudo xcode-select -s "$path"
actual="$(xcodebuild -version)"
if [[ "$actual" != "Xcode ${expected_version}"$'\n'"Build version ${expected_build}" ]]; then
  printf 'Pinned Xcode unavailable. Found: %s\n' "$actual" >&2
  exit 1
fi
printf '%s\n' "$actual"
