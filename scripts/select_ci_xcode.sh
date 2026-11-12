#!/usr/bin/env bash
set -euo pipefail
# Update deliberately together with the runtime and snapshot baselines.
expected_version=27.0
expected_build=27A266a
path="/Applications/Xcode_${expected_version}.0.app"
if [[ ! -d "$path" ]]; then path="/Applications/Xcode_27.app"; fi
if [[ ! -d "$path" ]]; then path=/Applications/Xcode.app; fi
sudo xcode-select -s "$path"
actual="$(xcodebuild -version)"
if [[ "$actual" != "Xcode ${expected_version}"$'\n'"Build version ${expected_build}" ]]; then
  printf 'Pinned Xcode unavailable. Found: %s\n' "$actual" >&2
  exit 1
fi
printf '%s\n' "$actual"
