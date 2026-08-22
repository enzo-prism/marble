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

DESTINATION=${DESTINATION:-$("${ROOT_DIR}/scripts/sim_destination.sh")}
DERIVED_DATA_PATH=${DERIVED_DATA_PATH:-"${ROOT_DIR}/DerivedData"}
mkdir -p "${DERIVED_DATA_PATH}"

RELEASE_EVIDENCE_RUN_DIR=${RELEASE_EVIDENCE_RUN_DIR:-}
RELEASE_EVIDENCE_SUITE=${RELEASE_EVIDENCE_SUITE:-test}

if [[ -n "${RELEASE_EVIDENCE_RUN_DIR}" && "${RELEASE_EVIDENCE_RUN_DIR}" != /* ]]; then
  echo "RELEASE_EVIDENCE_RUN_DIR must be an absolute path." >&2
  exit 1
fi

if [[ -n "${RELEASE_EVIDENCE_RUN_DIR}" && ! "${RELEASE_EVIDENCE_SUITE}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "RELEASE_EVIDENCE_SUITE must contain only letters, numbers, dots, underscores, and hyphens." >&2
  exit 1
fi

if [[ -n "${RELEASE_EVIDENCE_RUN_DIR}" ]]; then
  RESULT_BUNDLE_PATH=${RESULT_BUNDLE_PATH-"${RELEASE_EVIDENCE_RUN_DIR}/${RELEASE_EVIDENCE_SUITE}/Marble.xcresult"}
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

XCODEBUILD_CMD=(
  xcodebuild test
  "${PROJECT_ARGS[@]}"
  -scheme "$SCHEME"
  -destination "$DESTINATION"
  -configuration Debug
  -derivedDataPath "$DERIVED_DATA_PATH"
  -parallel-testing-enabled NO
  -enableCodeCoverage NO
)

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
  XCODEBUILD_CMD+=(-resultBundlePath "$RESULT_BUNDLE_PATH")
  echo "Result bundle: ${RESULT_BUNDLE_PATH}"
fi

XCODEBUILD_CMD+=("$@")

echo "Running: ${XCODEBUILD_CMD[*]}"

test_status=0
if command -v xcbeautify >/dev/null 2>&1; then
  set +e
  set -o pipefail
  "${XCODEBUILD_CMD[@]}" | xcbeautify
  pipeline_status=("${PIPESTATUS[@]}")
  set -e
  if (( pipeline_status[0] != 0 )); then
    test_status=${pipeline_status[0]}
  elif (( pipeline_status[1] != 0 )); then
    test_status=${pipeline_status[1]}
  fi
else
  set +e
  "${XCODEBUILD_CMD[@]}"
  test_status=$?
  set -e
fi

if ! verify_release_evidence_candidate; then
  exit 86
fi

exit "${test_status}"
