#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_REF="${MIGRATION_BASE_REF:-25a1c52}"
SIMULATOR_UDID="${SIMULATOR_UDID:-}"
RUN_ROOT="${MIGRATION_RUN_ROOT:-$ROOT_DIR/work}"
mkdir -p "$RUN_ROOT"
RUN_DIR="$(mktemp -d "$RUN_ROOT/release-migration.XXXXXX")"
BASE_DIR="$RUN_DIR/base"
BASE_DERIVED_DATA="$RUN_DIR/base-derived-data"
CANDIDATE_DERIVED_DATA="$RUN_DIR/candidate-derived-data"
BUNDLE_ID="Prism.marble"

cleanup() {
    xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl uninstall "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    git -C "$ROOT_DIR" worktree remove --force "$BASE_DIR" >/dev/null 2>&1 || true
    rm -rf "$RUN_DIR"
}
trap cleanup EXIT

if [[ -z "$SIMULATOR_UDID" ]]; then
    SIMULATOR_UDID="$(
        xcrun simctl list devices booted --json \
            | jq -r '[.devices[][] | select(.state == "Booted")][0].udid // empty'
    )"
fi

if [[ -z "$SIMULATOR_UDID" ]]; then
    echo "No booted iOS Simulator. Boot one or set SIMULATOR_UDID." >&2
    exit 1
fi

echo "Preparing previous Release source at $BASE_REF"
git -C "$ROOT_DIR" worktree add --detach "$BASE_DIR" "$BASE_REF" >/dev/null

echo "Building previous Release"
xcodebuild build \
    -project "$BASE_DIR/marble.xcodeproj" \
    -scheme marble \
    -configuration Release \
    -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
    -derivedDataPath "$BASE_DERIVED_DATA" \
    DEBUG_INFORMATION_FORMAT=dwarf \
    CODE_SIGNING_ALLOWED=NO \
    >"$RUN_DIR/base-build.log"

echo "Building candidate Release"
xcodebuild build \
    -project "$ROOT_DIR/marble.xcodeproj" \
    -scheme marble \
    -configuration Release \
    -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
    -derivedDataPath "$CANDIDATE_DERIVED_DATA" \
    DEBUG_INFORMATION_FORMAT=dwarf \
    CODE_SIGNING_ALLOWED=NO \
    >"$RUN_DIR/candidate-build.log"

BASE_APP="$BASE_DERIVED_DATA/Build/Products/Release-iphonesimulator/marble.app"
CANDIDATE_APP="$CANDIDATE_DERIVED_DATA/Build/Products/Release-iphonesimulator/marble.app"

for app in "$BASE_APP" "$CANDIDATE_APP"; do
    if [[ ! -d "$app" ]]; then
        echo "Expected app bundle was not produced: $app" >&2
        exit 1
    fi
    actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
    if [[ "$actual_bundle_id" != "$BUNDLE_ID" ]]; then
        echo "Unexpected bundle ID $actual_bundle_id in $app" >&2
        exit 1
    fi
done

xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "Launching previous Release to create its real store"
xcrun simctl install "$SIMULATOR_UDID" "$BASE_APP"
xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null
sleep 3
xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID"

DATA_DIR="$(xcrun simctl get_app_container "$SIMULATOR_UDID" "$BUNDLE_ID" data)"
STORE_PATH="$DATA_DIR/Library/Application Support/Marble/Marble.store"
if [[ ! -f "$STORE_PATH" ]]; then
    echo "Previous Release did not create its SwiftData store." >&2
    exit 1
fi
EXERCISE_COUNT_BEFORE="$(sqlite3 "$STORE_PATH" 'SELECT COUNT(*) FROM ZEXERCISE;')"

echo "Overlaying and launching candidate Release"
xcrun simctl install "$SIMULATOR_UDID" "$CANDIDATE_APP"
START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
LAUNCH_OUTPUT="$(xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID")"
APP_PID="${LAUNCH_OUTPUT##*: }"
sleep 3

if ! kill -0 "$APP_PID" >/dev/null 2>&1; then
    echo "Candidate terminated during the previous-Release migration." >&2
    exit 1
fi

LAUNCH_LOG="$RUN_DIR/candidate-launch.log"
xcrun simctl spawn "$SIMULATOR_UDID" log show \
    --style compact \
    --start "$START_TIME" \
    --predicate 'process == "marble"' \
    >"$LAUNCH_LOG"

if rg -q 'Duplicate version checksums|Terminating app|uncaught exception' "$LAUNCH_LOG"; then
    echo "Candidate logged a launch crash during migration:" >&2
    rg 'Duplicate version checksums|Terminating app|uncaught exception' "$LAUNCH_LOG" >&2
    exit 1
fi

# Simulator may move the retained data container to a new UUID when overlaying the app.
DATA_DIR="$(xcrun simctl get_app_container "$SIMULATOR_UDID" "$BUNDLE_ID" data)"
STORE_PATH="$DATA_DIR/Library/Application Support/Marble/Marble.store"
if ! sqlite3 "$STORE_PATH" ".tables" | tr ' ' '\n' | rg -qx 'ZWORKOUTSESSION'; then
    echo "Candidate did not create the WorkoutSession table." >&2
    exit 1
fi
if ! sqlite3 "$STORE_PATH" ".tables" | tr ' ' '\n' | rg -qx 'ZSPRINTPRESCRIPTION'; then
    echo "Candidate did not create the SprintPrescription table." >&2
    exit 1
fi

EXERCISE_COUNT_AFTER="$(sqlite3 "$STORE_PATH" 'SELECT COUNT(*) FROM ZEXERCISE;')"
if [[ "$EXERCISE_COUNT_AFTER" != "$EXERCISE_COUNT_BEFORE" ]]; then
    echo "Exercise data changed during migration: $EXERCISE_COUNT_BEFORE -> $EXERCISE_COUNT_AFTER" >&2
    exit 1
fi

echo "Release migration passed: $BASE_REF -> candidate; exercises preserved=$EXERCISE_COUNT_AFTER"
