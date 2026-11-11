#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

SCHEME=${SCHEME:-marble}

if [[ -n "${WORKSPACE:-}" ]]; then
  PROJECT_ARGS=(-workspace "$WORKSPACE")
elif [[ -d "${ROOT_DIR}/marble.xcworkspace" ]]; then
  PROJECT_ARGS=(-workspace "${ROOT_DIR}/marble.xcworkspace")
elif [[ -n "${PROJECT:-}" ]]; then
  PROJECT_ARGS=(-project "$PROJECT")
elif [[ -d "${ROOT_DIR}/marble.xcodeproj" ]]; then
  PROJECT_ARGS=(-project "${ROOT_DIR}/marble.xcodeproj")
else
  echo "No .xcworkspace or .xcodeproj found. Set WORKSPACE or PROJECT." >&2
  exit 1
fi

DERIVED_DATA_PATH=${DERIVED_DATA_PATH:-"${ROOT_DIR}/DerivedData"}
mkdir -p "${DERIVED_DATA_PATH}"

refresh_simulator_destination() {
  if [[ -n "${DESTINATION:-}" && "${DESTINATION}" != id=* ]]; then
    return 0
  fi
  if [[ "${DESTINATION:-}" == id=* ]]; then
    export MARBLE_SIMULATOR_ID="${MARBLE_SIMULATOR_ID:-${DESTINATION#id=}}"
  fi
  DESTINATION=$("${ROOT_DIR}/scripts/ensure_simulator.sh")
  export MARBLE_SIMULATOR_ID="${DESTINATION#id=}"
  # History snapshots flip the device content size to XXXL. That setting
  # survives shutdown/boot on current macos-26 images, so every later
  # xcodebuild must put it back before launching the runner.
  if [[ "${MARBLE_SKIP_CONTENT_SIZE_RESET:-0}" != "1" ]]; then
    desired_size="${MARBLE_SIMULATOR_CONTENT_SIZE:-large}"
    "${ROOT_DIR}/scripts/reset_simulator_ui.sh" "${desired_size}"
  fi
}

refresh_simulator_destination

RELEASE_EVIDENCE_RUN_DIR=${RELEASE_EVIDENCE_RUN_DIR:-}
RELEASE_EVIDENCE_SUITE=${RELEASE_EVIDENCE_SUITE:-test}
RELEASE_EVIDENCE_CAPTURE_XCRESULT=${RELEASE_EVIDENCE_CAPTURE_XCRESULT:-1}

if [[ -n "${RELEASE_EVIDENCE_RUN_DIR}" && "${RELEASE_EVIDENCE_RUN_DIR}" != /* ]]; then
  echo "RELEASE_EVIDENCE_RUN_DIR must be an absolute path." >&2
  exit 1
fi

if [[ -n "${RELEASE_EVIDENCE_RUN_DIR}" && ! "${RELEASE_EVIDENCE_SUITE}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "RELEASE_EVIDENCE_SUITE must contain only letters, numbers, dots, underscores, and hyphens." >&2
  exit 1
fi

if [[ "${RELEASE_EVIDENCE_CAPTURE_XCRESULT}" != "0" && "${RELEASE_EVIDENCE_CAPTURE_XCRESULT}" != "1" ]]; then
  echo "RELEASE_EVIDENCE_CAPTURE_XCRESULT must be 0 or 1." >&2
  exit 1
fi

if [[ -n "${RELEASE_EVIDENCE_RUN_DIR}" ]]; then
  if [[ "${RELEASE_EVIDENCE_CAPTURE_XCRESULT}" == "0" ]]; then
    RESULT_BUNDLE_PATH=""
  else
    RESULT_BUNDLE_PATH=${RESULT_BUNDLE_PATH-"${RELEASE_EVIDENCE_RUN_DIR}/${RELEASE_EVIDENCE_SUITE}/Marble.xcresult"}
  fi
else
  RESULT_BUNDLE_PATH=${RESULT_BUNDLE_PATH-"${ROOT_DIR}/TestResults/Marble.xcresult"}
fi

verify_release_evidence_candidate() {
  [[ -n "${RELEASE_EVIDENCE_RUN_DIR}" ]] || return 0

  local actual_sha actual_build
  actual_sha=$(git -C "${ROOT_DIR}" rev-parse HEAD)
  actual_build=$(ruby -e '
    project = File.read(ARGV[0])
    values = project.scan(/CURRENT_PROJECT_VERSION = ([^;]+);/).flatten.map(&:strip).uniq
    abort("CURRENT_PROJECT_VERSION not found") if values.empty?
    abort("CURRENT_PROJECT_VERSION values disagree: #{values.join(", ")}") if values.length != 1
    print values.first
  ' "${ROOT_DIR}/marble.xcodeproj/project.pbxproj")

  if [[ -n "${RELEASE_EVIDENCE_EXPECTED_SHA:-}" && "${actual_sha}" != "${RELEASE_EVIDENCE_EXPECTED_SHA}" ]]; then
    echo "Release evidence candidate changed: expected ${RELEASE_EVIDENCE_EXPECTED_SHA}, found ${actual_sha}." >&2
    return 1
  fi
  if [[ -n "${RELEASE_EVIDENCE_EXPECTED_BUILD:-}" && "${actual_build}" != "${RELEASE_EVIDENCE_EXPECTED_BUILD}" ]]; then
    echo "Release evidence build changed: expected ${RELEASE_EVIDENCE_EXPECTED_BUILD}, found ${actual_build}." >&2
    return 1
  fi
}

verify_release_evidence_candidate

# Xcode still creates a DerivedData result bundle when no explicit
# -resultBundlePath is supplied. For long release-evidence UI suites, prevent
# post-test sysdiagnose collection from turning an otherwise-green run into a
# multi-gigabyte ENOSPC failure. Unit and snapshot evidence continue to retain
# their explicit xcresult bundles.
if [[ -n "${RELEASE_EVIDENCE_RUN_DIR}" && "${RELEASE_EVIDENCE_CAPTURE_XCRESULT}" == "0" ]]; then
  RESULT_BUNDLE_COLLECT_NEVER=1
else
  RESULT_BUNDLE_COLLECT_NEVER=0
fi

# An explicitly empty path keeps focused reruns low-artifact when Xcode result
# recording is unavailable. Normal developer runs still replace the single
# checkout-local bundle above. Release-evidence runs refuse to overwrite any
# artifact because their run directory is an immutable audit record.
if [[ -n "$RESULT_BUNDLE_PATH" ]]; then
  mkdir -p "$(dirname "${RESULT_BUNDLE_PATH}")"
  if [[ -e "${RESULT_BUNDLE_PATH}" ]]; then
    if [[ -n "${RELEASE_EVIDENCE_RUN_DIR}" ]]; then
      echo "Refusing to overwrite release evidence: ${RESULT_BUNDLE_PATH}" >&2
      exit 1
    fi
    rm -rf "${RESULT_BUNDLE_PATH}"
  fi
  echo "Result bundle: ${RESULT_BUNDLE_PATH}"
fi

build_xcodebuild_cmd() {
  XCODEBUILD_CMD=(
    xcodebuild test
    "${PROJECT_ARGS[@]}"
    -scheme "$SCHEME"
    -destination "$DESTINATION"
    -configuration Debug
    -derivedDataPath "$DERIVED_DATA_PATH"
    -parallel-testing-enabled NO
    -enableCodeCoverage NO
    -test-timeouts-enabled YES
    -default-test-execution-time-allowance "${MARBLE_TEST_EXECUTION_TIMEOUT:-900}"
    -maximum-test-execution-time-allowance "${MARBLE_TEST_EXECUTION_TIMEOUT:-900}"
  )
  if [[ "${RESULT_BUNDLE_COLLECT_NEVER}" == "1" ]]; then
    XCODEBUILD_CMD+=(-collect-test-diagnostics never)
  fi
  if [[ -n "$RESULT_BUNDLE_PATH" ]]; then
    XCODEBUILD_CMD+=(-resultBundlePath "$RESULT_BUNDLE_PATH")
  fi
  XCODEBUILD_CMD+=("$@")
}

run_xcodebuild() {
  echo "Running: ${XCODEBUILD_CMD[*]}"
  test_status=0
  : >"${xcodebuild_log}"
  if command -v xcbeautify >/dev/null 2>&1; then
    set +e
    set -o pipefail
    "${XCODEBUILD_CMD[@]}" 2>&1 | tee "${xcodebuild_log}" | xcbeautify
    pipeline_status=("${PIPESTATUS[@]}")
    set -e
    if (( pipeline_status[0] != 0 )); then
      test_status=${pipeline_status[0]}
    elif (( pipeline_status[2] != 0 )); then
      test_status=${pipeline_status[2]}
    fi
  else
    set +e
    "${XCODEBUILD_CMD[@]}" 2>&1 | tee "${xcodebuild_log}"
    pipeline_status=("${PIPESTATUS[@]}")
    set -e
    test_status=${pipeline_status[0]}
  fi
}

xcodebuild_log=$(mktemp)
trap 'rm -f "${xcodebuild_log}"' EXIT

test_status=0
attempt=1
while true; do
  build_xcodebuild_cmd "$@"
  run_xcodebuild
  if (( test_status == 0 )); then
    break
  fi
  if (( attempt >= 2 )) || ! grep -q "Unable to find a device matching the provided destination specifier" "${xcodebuild_log}"; then
    break
  fi
  echo "xcodebuild lost every simulator destination; waiting for CoreSimulator and retrying once." >&2
  if [[ -n "${RESULT_BUNDLE_PATH:-}" ]]; then
    rm -rf "${RESULT_BUNDLE_PATH}"
  fi
  unset DESTINATION
  refresh_simulator_destination
  attempt=$((attempt + 1))
done

if ! verify_release_evidence_candidate; then
  exit 86
fi

exit "${test_status}"
