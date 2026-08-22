#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST_TOOL="${ROOT_DIR}/scripts/release_evidence_manifest.rb"

usage() {
  cat <<'EOF'
Usage:
  scripts/release_evidence.sh run
  scripts/release_evidence.sh verify /absolute/path/to/manifest.json

Environment for `run`:
  RELEASE_EVIDENCE_ROOT        Absolute evidence root (default: TestResults/release-gates)
  RELEASE_EVIDENCE_GATES       Space-separated gates (default: unit snapshot ui accessibility migration)
  RELEASE_EVIDENCE_ALLOW_DIRTY Set to 1 only for non-release workflow development
  DERIVED_DATA_PATH            Optional dedicated DerivedData path
  MARBLE_SIMULATOR_ID          Dedicated simulator for test/snapshot/UI/audit gates
  MIGRATION_BASE_REF           Optional shipped-source migration base
  SIMULATOR_UDID               Migration simulator (defaults to MARBLE_SIMULATOR_ID)

Unit and snapshot gates retain xcresult bundles. UI and accessibility gates retain
complete command logs and exit status without xcresult attachments, which can grow
by multiple gigabytes when UI screenshots and hierarchy diagnostics are embedded.
EOF
}

iso8601_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

project_value() {
  local key="$1"
  ruby -e '
    project = File.read(ARGV[0])
    key = ARGV[1]
    values = project.scan(/#{Regexp.escape(key)} = ([^;]+);/).flatten.map(&:strip).uniq
    abort("#{key} not found") if values.empty?
    abort("#{key} values disagree: #{values.join(", ")}") if values.length != 1
    print values.first
  ' "${ROOT_DIR}/marble.xcodeproj/project.pbxproj" "${key}"
}

write_gate_record() {
  local gate="$1"
  local status="$2"
  local exit_code="$3"
  local started_at="$4"
  local completed_at="$5"
  local command_text="$6"
  local reason="${7:-}"
  local output_path="${RELEASE_EVIDENCE_RUN_DIR}/.evidence/gates/${gate}.json"

  jq -n \
    --arg name "${gate}" \
    --arg status "${status}" \
    --argjson exitCode "${exit_code}" \
    --arg startedAt "${started_at}" \
    --arg completedAt "${completed_at}" \
    --arg command "${command_text}" \
    --arg reason "${reason}" \
    '{name: $name, status: $status, exit_code: $exitCode, started_at: $startedAt,
      completed_at: $completedAt, command: $command,
      reason: (if $reason == "" then null else $reason end)}' >"${output_path}"
}

candidate_is_unchanged() {
  [[ "$(git -C "${ROOT_DIR}" rev-parse HEAD)" == "${RELEASE_EVIDENCE_EXPECTED_SHA}" ]] || return 1
  [[ "$(project_value CURRENT_PROJECT_VERSION)" == "${RELEASE_EVIDENCE_EXPECTED_BUILD}" ]] || return 1
  if [[ "${RELEASE_EVIDENCE_ALLOW_DIRTY:-0}" != "1" ]]; then
    git -C "${ROOT_DIR}" diff --quiet --ignore-submodules -- &&
      git -C "${ROOT_DIR}" diff --cached --quiet --ignore-submodules -- &&
      [[ -z "$(git -C "${ROOT_DIR}" ls-files --others --exclude-standard)" ]]
  fi
}

run_gate() {
  local gate="$1"
  shift
  local started_at completed_at status command_text log_path
  local -a snapshot_results
  local exit_code=0
  started_at=$(iso8601_now)
  log_path="${RELEASE_EVIDENCE_RUN_DIR}/${gate}/command.log"
  mkdir -p "$(dirname "${log_path}")"
  printf -v command_text '%q ' "$@"
  command_text=${command_text% }

  echo "==> ${gate}: ${command_text}"
  set +e
  "$@" 2>&1 | tee "${log_path}"
  pipeline_status=("${PIPESTATUS[@]}")
  set -e
  exit_code=${pipeline_status[0]}
  completed_at=$(iso8601_now)

  if (( exit_code == 0 )); then
    status=passed
  else
    status=failed
  fi

  if (( exit_code == 0 )); then
    case "${gate}" in
      unit)
        if [[ ! -d "${RELEASE_EVIDENCE_RUN_DIR}/${gate}/Marble.xcresult" ]]; then
          status=failed
          exit_code=87
          printf '%s\n' "Expected ${gate} xcresult was not produced." | tee -a "${log_path}" >&2
        fi
        ;;
      ui|accessibility)
        if [[ ! -s "${log_path}" ]]; then
          status=failed
          exit_code=87
          printf '%s\n' "Expected ${gate} command log was empty." | tee -a "${log_path}" >&2
        fi
        ;;
      snapshot)
        snapshot_results=("${RELEASE_EVIDENCE_RUN_DIR}/${gate}/"*.xcresult)
        if [[ ! -d "${snapshot_results[0]}" ]]; then
          status=failed
          exit_code=87
          printf '%s\n' "Expected snapshot xcresults were not produced." | tee -a "${log_path}" >&2
        fi
        ;;
      migration)
        if [[ ! -s "${log_path}" ]]; then
          status=failed
          exit_code=87
          printf '%s\n' "Expected migration log was empty." | tee -a "${log_path}" >&2
        fi
        ;;
    esac
  fi

  if ! candidate_is_unchanged; then
    status=failed
    exit_code=86
    printf '%s\n' "Candidate identity or clean-worktree state changed while ${gate} ran." | tee -a "${log_path}" >&2
    CANDIDATE_DRIFTED=1
  fi

  write_gate_record "${gate}" "${status}" "${exit_code}" "${started_at}" "${completed_at}" "${command_text}"
  if (( exit_code != 0 )); then
    OVERALL_STATUS=failed
  fi
}

skip_gate() {
  local gate="$1"
  local reason="$2"
  local now
  now=$(iso8601_now)
  mkdir -p "${RELEASE_EVIDENCE_RUN_DIR}/${gate}"
  printf '%s\n' "${reason}" >"${RELEASE_EVIDENCE_RUN_DIR}/${gate}/command.log"
  write_gate_record "${gate}" skipped 0 "${now}" "${now}" "" "${reason}"
  OVERALL_STATUS=failed
}

run_release_evidence() {
  for required in git jq ruby make; do
    command -v "${required}" >/dev/null 2>&1 || {
      echo "Required command not found: ${required}" >&2
      exit 1
    }
  done

  local evidence_root candidate_sha build_number marketing_version started_at run_stamp
  local gate requested_gates_json seen_gates
  local -a gates
  evidence_root=${RELEASE_EVIDENCE_ROOT:-"${ROOT_DIR}/TestResults/release-gates"}
  if [[ "${evidence_root}" != /* ]]; then
    echo "RELEASE_EVIDENCE_ROOT must be an absolute path: ${evidence_root}" >&2
    exit 1
  fi

  candidate_sha=$(git -C "${ROOT_DIR}" rev-parse HEAD)
  build_number=$(project_value CURRENT_PROJECT_VERSION)
  marketing_version=$(project_value MARKETING_VERSION)
  started_at=$(iso8601_now)
  run_stamp=$(date -u '+%Y%m%dT%H%M%SZ')
  read -r -a gates <<<"${RELEASE_EVIDENCE_GATES:-unit snapshot ui accessibility migration}"
  if (( ${#gates[@]} == 0 )); then
    echo "RELEASE_EVIDENCE_GATES must select at least one gate." >&2
    exit 1
  fi
  seen_gates=" "
  for gate in "${gates[@]}"; do
    case "${gate}" in
      unit|snapshot|ui|accessibility|migration) ;;
      *)
        echo "Unknown release evidence gate: ${gate}" >&2
        exit 1
        ;;
    esac
    if [[ "${seen_gates}" == *" ${gate} "* ]]; then
      echo "Duplicate release evidence gate: ${gate}" >&2
      exit 1
    fi
    seen_gates+="${gate} "
  done
  requested_gates_json=$(printf '%s\n' "${gates[@]}" | jq -R -s 'split("\n") | map(select(length > 0))')

  if [[ "${RELEASE_EVIDENCE_ALLOW_DIRTY:-0}" != "1" ]]; then
    if ! git -C "${ROOT_DIR}" diff --quiet --ignore-submodules -- ||
      ! git -C "${ROOT_DIR}" diff --cached --quiet --ignore-submodules -- ||
      [[ -n "$(git -C "${ROOT_DIR}" ls-files --others --exclude-standard)" ]]; then
      echo "Release evidence requires a clean worktree. Commit or remove candidate changes first." >&2
      exit 1
    fi
  fi

  mkdir -p "${evidence_root}/${candidate_sha}/build-${build_number}"
  RELEASE_EVIDENCE_RUN_DIR=$(mktemp -d "${evidence_root}/${candidate_sha}/build-${build_number}/${run_stamp}.XXXXXX")
  export RELEASE_EVIDENCE_RUN_DIR
  export RELEASE_EVIDENCE_EXPECTED_SHA="${candidate_sha}"
  export RELEASE_EVIDENCE_EXPECTED_BUILD="${build_number}"
  export RELEASE_EVIDENCE_ALLOW_DIRTY="${RELEASE_EVIDENCE_ALLOW_DIRTY:-0}"
  unset RESULT_BUNDLE_PATH
  if [[ -n "${MARBLE_SIMULATOR_ID:-}" && -z "${SIMULATOR_UDID:-}" ]]; then
    export SIMULATOR_UDID="${MARBLE_SIMULATOR_ID}"
  fi
  mkdir -p "${RELEASE_EVIDENCE_RUN_DIR}/.evidence/gates"

  jq -n \
    --arg schemaVersion "1" \
    --arg startedAt "${started_at}" \
    --arg repository "${ROOT_DIR}" \
    --arg gitSha "${candidate_sha}" \
    --arg buildNumber "${build_number}" \
    --arg marketingVersion "${marketing_version}" \
    --arg runId "$(basename "${RELEASE_EVIDENCE_RUN_DIR}")" \
    --argjson requestedGates "${requested_gates_json}" \
    '{schema_version: ($schemaVersion | tonumber), started_at: $startedAt,
      repository: $repository, git_sha: $gitSha, build_number: $buildNumber,
      marketing_version: $marketingVersion, run_id: $runId,
      requested_gates: $requestedGates}' \
    >"${RELEASE_EVIDENCE_RUN_DIR}/.evidence/run.json"

  echo "Release evidence run: ${RELEASE_EVIDENCE_RUN_DIR}"
  OVERALL_STATUS=passed
  CANDIDATE_DRIFTED=0
  for gate in "${gates[@]}"; do
    if (( CANDIDATE_DRIFTED != 0 )); then
      skip_gate "${gate}" "Skipped because the candidate changed during an earlier gate."
      continue
    fi

    export RELEASE_EVIDENCE_SUITE="${gate}"
    case "${gate}" in
      unit)
        run_gate "${gate}" make -C "${ROOT_DIR}" unit
        ;;
      snapshot)
        run_gate "${gate}" env SNAPSHOT_SUITE=full SNAPSHOT_GROUPS_OVERRIDE= RECORD_SNAPSHOTS= SNAPSHOT_TESTING_RECORD= make -C "${ROOT_DIR}" snapshot
        ;;
      ui)
        run_gate "${gate}" env RELEASE_EVIDENCE_CAPTURE_XCRESULT=0 make -C "${ROOT_DIR}" ui
        ;;
      accessibility)
        run_gate "${gate}" env RELEASE_EVIDENCE_CAPTURE_XCRESULT=0 make -C "${ROOT_DIR}" audit
        ;;
      migration)
        run_gate "${gate}" make -C "${ROOT_DIR}" migration-release
        ;;
    esac
  done

  "${MANIFEST_TOOL}" generate "${RELEASE_EVIDENCE_RUN_DIR}"
  "${MANIFEST_TOOL}" verify "${RELEASE_EVIDENCE_RUN_DIR}/manifest.json"
  echo "Release evidence manifest: ${RELEASE_EVIDENCE_RUN_DIR}/manifest.json"

  [[ "${OVERALL_STATUS}" == passed ]]
}

case "${1:-}" in
  run)
    run_release_evidence
    ;;
  verify)
    [[ $# -eq 2 ]] || { usage >&2; exit 1; }
    "${MANIFEST_TOOL}" verify "$2"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
