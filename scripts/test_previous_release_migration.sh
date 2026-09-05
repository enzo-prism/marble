#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The newest source a real user can already be running: App Store 2.4 build 61.
# Refreshed against ASC September 4, 2026. The default gate is the upgrade
# every current install performs. Point MIGRATION_BASE_REF at an older release
# to widen the check.
BASE_REF="${MIGRATION_BASE_REF:-9e8346f6cad4683991a78fbaf223baaf01e9f068}"
SIMULATOR_UDID="${SIMULATOR_UDID:-}"
RUN_ROOT="${MIGRATION_RUN_ROOT:-$ROOT_DIR/work}"
if [[ -n "${RELEASE_EVIDENCE_RUN_DIR:-}" && -z "${MIGRATION_RUN_ROOT:-}" ]]; then
    RUN_ROOT="$RELEASE_EVIDENCE_RUN_DIR/migration/details"
fi
mkdir -p "$RUN_ROOT"
RUN_DIR="$(mktemp -d "$RUN_ROOT/release-migration.XXXXXX")"
BASE_DIR="$RUN_DIR/base"
BUILD_ROOT="${MIGRATION_DERIVED_DATA_ROOT:-$RUN_DIR}"
mkdir -p "$BUILD_ROOT"
BUILD_DIR="$(mktemp -d "$BUILD_ROOT/marble-migration-build.XXXXXX")"
BASE_DERIVED_DATA="$BUILD_DIR/base-derived-data"
CANDIDATE_DERIVED_DATA="$BUILD_DIR/candidate-derived-data"
BUNDLE_ID="Prism.marble"
PROBE_TOKEN="$(uuidgen)"
EXPECTED_PROBE="$RUN_DIR/expected-probe.json"

cleanup() {
    xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl uninstall "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    git -C "$ROOT_DIR" worktree remove --force "$BASE_DIR" >/dev/null 2>&1 || true
    # Preserve logs and build evidence for diagnosis; callers may review and
    # remove these exact generated paths after release verification.
    printf 'Migration evidence: %s\nMigration builds: %s\n' "$RUN_DIR" "$BUILD_DIR"
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
    ONLY_ACTIVE_ARCH=YES \
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
    ONLY_ACTIVE_ARCH=YES \
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

# Release builds do not require the destination to remain booted. Re-establish
# a ready Simulator immediately before the install/launch migration sequence.
xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
xcrun simctl terminate "$SIMULATOR_UDID" Prism.marbleUITests.xctrunner >/dev/null 2>&1 || true

xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "Launching previous Release to create its real store"
xcrun simctl install "$SIMULATOR_UDID" "$BASE_APP"
BASE_START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
BASE_LAUNCH_OUTPUT="$(xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID")"
BASE_APP_PID="${BASE_LAUNCH_OUTPUT##*: }"

DATA_DIR="$(xcrun simctl get_app_container "$SIMULATOR_UDID" "$BUNDLE_ID" data)"
STORE_PATH="$DATA_DIR/Library/Application Support/Marble/Marble.store"
# A cold Release launch can take longer than a fixed sleep while Simulator is
# settling after the two archive builds. Poll until the async first-run seed is
# durable, not merely until SQLite creates the file, so launch speed does not
# decide whether a valid migration passes.
EXERCISE_COUNT_BEFORE=""
for _ in {1..15}; do
    if [[ -f "$STORE_PATH" ]]; then
        candidate_count="$(sqlite3 "$STORE_PATH" 'SELECT COUNT(*) FROM ZEXERCISE;' 2>/dev/null || true)"
        if [[ "$candidate_count" =~ ^[0-9]+$ ]] && (( candidate_count > 0 )); then
            EXERCISE_COUNT_BEFORE="$candidate_count"
            break
        fi
    fi
    kill -0 "$BASE_APP_PID" >/dev/null 2>&1 || break
    sleep 1
done
if [[ -z "$EXERCISE_COUNT_BEFORE" ]]; then
    echo "Previous Release did not create and seed its SwiftData store." >&2
    if ! kill -0 "$BASE_APP_PID" >/dev/null 2>&1; then
        echo "Previous Release terminated before creating its store." >&2
    fi
    echo "Application Support contents:" >&2
    find "$DATA_DIR/Library/Application Support" -maxdepth 3 -print >&2 || true
    echo "Previous Release launch log:" >&2
    xcrun simctl spawn "$SIMULATOR_UDID" log show \
        --style compact \
        --start "$BASE_START_TIME" \
        --predicate 'process == "marble"' \
        >&2 || true
    exit 1
fi
xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID"

# Populate only this disposable simulator store, while its owning process is stopped.
# Keep a real user-created completed session and a user-edited exercise, rather than
# relying on the default seed count (which a destructive reset can reproduce).
sqlite3 "$STORE_PATH" '.schema' >"$RUN_DIR/base-schema.sql"
sqlite3 "$STORE_PATH" <<SQL
.bail on
BEGIN IMMEDIATE;
UPDATE ZEXERCISE SET ZNAME = 'Migration exercise $PROBE_TOKEN' WHERE Z_PK = (SELECT MIN(Z_PK) FROM ZEXERCISE);
INSERT INTO ZWORKOUTSESSION (Z_PK, Z_ENT, Z_OPT, ZID, ZTITLE, ZSTARTEDAT, ZENDEDAT, ZNOTES, ZCREATEDAT, ZUPDATEDAT)
SELECT Z_MAX + 1, Z_ENT, 1, X'${PROBE_TOKEN//-/}', 'Migration workout $PROBE_TOKEN', 800000000, 800003600, 'Retain my completed workout', 800000000, 800003600
FROM Z_PRIMARYKEY WHERE Z_NAME = 'WorkoutSession';
UPDATE Z_PRIMARYKEY SET Z_MAX = Z_MAX + 1 WHERE Z_NAME = 'WorkoutSession';
COMMIT;
SQL
snapshot_user_rows() {
    sqlite3 "$1" "SELECT json_object(
      'exercise_id', hex(e.ZID), 'exercise_name', e.ZNAME,
      'session_id', hex(s.ZID), 'session_title', s.ZTITLE, 'session_notes', s.ZNOTES,
      'session_started_at', s.ZSTARTEDAT, 'session_ended_at', s.ZENDEDAT)
      FROM ZEXERCISE e CROSS JOIN ZWORKOUTSESSION s
      WHERE e.ZNAME = 'Migration exercise $PROBE_TOKEN' AND s.ZID = X'${PROBE_TOKEN//-/}';"
}
snapshot_user_rows "$STORE_PATH" >"$EXPECTED_PROBE"
[[ -s "$EXPECTED_PROBE" ]] || { echo "Could not create migration user fixture." >&2; exit 1; }
STORE_UUID_BEFORE="$(sqlite3 "$STORE_PATH" 'SELECT Z_UUID FROM Z_METADATA;')"
[[ -n "$STORE_UUID_BEFORE" ]] || { echo "Base store has no identity." >&2; exit 1; }

# Reopen the immutable shipped app with the fixture before attempting the upgrade.
# Any destructive recovery is caught by the retained rows and store UUID below.
BASE_FIXTURE_LAUNCH="$(xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID")"
printf '%s\n' "$BASE_FIXTURE_LAUNCH" >"$RUN_DIR/base-fixture-launch.log"
BASE_FIXTURE_PID="${BASE_FIXTURE_LAUNCH##*: }"
BASE_FIXTURE_OPEN=false
for _ in {1..15}; do
    kill -0 "$BASE_FIXTURE_PID" >/dev/null 2>&1 || break
    if lsof -a -p "$BASE_FIXTURE_PID" "$STORE_PATH" >"$RUN_DIR/base-fixture-open-files.log" 2>/dev/null; then
        BASE_FIXTURE_OPEN=true
        break
    fi
    sleep 1
done
[[ "$BASE_FIXTURE_OPEN" == true ]] || { echo "Base app did not reopen its fixture store." >&2; exit 1; }
xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID"
[[ "$(snapshot_user_rows "$STORE_PATH")" == "$(cat "$EXPECTED_PROBE")" ]] || { echo "Base app changed the fixture." >&2; exit 1; }
[[ "$(sqlite3 "$STORE_PATH" 'SELECT Z_UUID FROM Z_METADATA;')" == "$STORE_UUID_BEFORE" ]] || { echo "Base app replaced its store." >&2; exit 1; }

# A prior marker must never satisfy a new run, even if the container is retained.
rm -f "$(dirname "$STORE_PATH")/migration-probe.json"
echo "Overlaying and launching candidate Release"
xcrun simctl install "$SIMULATOR_UDID" "$CANDIDATE_APP"
START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
LAUNCH_OUTPUT="$(SIMCTL_CHILD_MARBLE_MIGRATION_PROBE="$PROBE_TOKEN" xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID")"
APP_PID="${LAUNCH_OUTPUT##*: }"

CANDIDATE_READY=false
for _ in {1..15}; do
    DATA_DIR="$(xcrun simctl get_app_container "$SIMULATOR_UDID" "$BUNDLE_ID" data)"
    STORE_PATH="$DATA_DIR/Library/Application Support/Marble/Marble.store"
    if [[ -f "$STORE_PATH" ]]; then
        candidate_tables="$(sqlite3 "$STORE_PATH" '.tables' 2>/dev/null || true)"
        candidate_count="$(sqlite3 "$STORE_PATH" 'SELECT COUNT(*) FROM ZEXERCISE;' 2>/dev/null || true)"
        if kill -0 "$APP_PID" >/dev/null 2>&1 \
            && ruby "$ROOT_DIR/scripts/verify_migration_probe.rb" "$EXPECTED_PROBE" \
                "$(dirname "$STORE_PATH")/migration-probe.json" "$PROBE_TOKEN" "$APP_PID" "$STORE_PATH" \
                2>"$RUN_DIR/probe-readiness.log" \
            && grep -qw 'ZWORKOUTSESSION' <<<"$candidate_tables" \
            && grep -qw 'ZSPRINTPRESCRIPTION' <<<"$candidate_tables" \
            && grep -qw 'ZBODYMETRICENTRY' <<<"$candidate_tables" \
            && [[ "$candidate_count" == "$EXERCISE_COUNT_BEFORE" ]]; then
            CANDIDATE_READY=true
            break
        fi
    fi
    kill -0 "$APP_PID" >/dev/null 2>&1 || break
    sleep 1
done

if [[ "$CANDIDATE_READY" != true ]]; then
    if ! kill -0 "$APP_PID" >/dev/null 2>&1; then
        echo "Candidate terminated during the previous-Release migration." >&2
    else
        echo "Candidate did not finish migrating the previous-Release store." >&2
    fi
    exit 1
fi

kill -0 "$APP_PID" >/dev/null 2>&1 || { echo "Candidate exited after readiness." >&2; exit 1; }
[[ "$(snapshot_user_rows "$STORE_PATH")" == "$(cat "$EXPECTED_PROBE")" ]] || { echo "Candidate changed retained user rows." >&2; exit 1; }
[[ "$(sqlite3 "$STORE_PATH" 'SELECT Z_UUID FROM Z_METADATA;')" == "$STORE_UUID_BEFORE" ]] || { echo "Candidate replaced the persistent store." >&2; exit 1; }
cp "$(dirname "$STORE_PATH")/migration-probe.json" "$RUN_DIR/candidate-probe.json"

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

# Simulator may move the retained data container to a new UUID when overlaying the app;
# the readiness loop above refreshes these paths on every attempt.
if ! sqlite3 "$STORE_PATH" ".tables" | tr ' ' '\n' | rg -qx 'ZWORKOUTSESSION'; then
    echo "Candidate did not create the WorkoutSession table." >&2
    exit 1
fi
if ! sqlite3 "$STORE_PATH" ".tables" | tr ' ' '\n' | rg -qx 'ZSPRINTPRESCRIPTION'; then
    echo "Candidate did not create the SprintPrescription table." >&2
    exit 1
fi
# V5's additive table. A shipping schema whose newest entity never appears has
# not actually migrated — it has silently opened as the older schema.
if ! sqlite3 "$STORE_PATH" ".tables" | tr ' ' '\n' | rg -qx 'ZBODYMETRICENTRY'; then
    echo "Candidate did not create the BodyMetricEntry table (V5 did not migrate)." >&2
    exit 1
fi

EXERCISE_COUNT_AFTER="$(sqlite3 "$STORE_PATH" 'SELECT COUNT(*) FROM ZEXERCISE;')"
if [[ "$EXERCISE_COUNT_AFTER" != "$EXERCISE_COUNT_BEFORE" ]]; then
    echo "Exercise data changed during migration: $EXERCISE_COUNT_BEFORE -> $EXERCISE_COUNT_AFTER" >&2
    exit 1
fi

echo "Release migration passed: $BASE_REF -> candidate; exercises preserved=$EXERCISE_COUNT_AFTER"
