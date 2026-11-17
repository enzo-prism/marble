#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST_TOOL="${ROOT_DIR}/scripts/release_evidence_manifest.rb"

usage() {
  cat <<'EOF'
Usage:
  scripts/release_evidence.sh init
  scripts/release_evidence.sh run
  scripts/release_evidence.sh assemble /absolute/path/to/gate-fragments
  scripts/release_evidence.sh finalize
  scripts/release_evidence.sh verify /absolute/path/to/manifest.json

Environment for `run` / `init` / `finalize` / `assemble`:
  RELEASE_EVIDENCE_ROOT        Absolute evidence root (default: TestResults/release-gates)
  RELEASE_EVIDENCE_CONTINUE_DIR Absolute run dir from `init` (required for split CI gates)
  RELEASE_EVIDENCE_GATES       Space-separated gates (default: unit snapshot ui accessibility migration)
  RELEASE_EVIDENCE_DEFER_MANIFEST Set to 1 to skip generate/verify until `finalize`
  RELEASE_EVIDENCE_UI_SHARD    1, 2, or 3 to run one UI class shard
  RELEASE_EVIDENCE_ALLOW_DIRTY Set to 1 only for non-release workflow development
  DERIVED_DATA_PATH            Optional dedicated DerivedData path
  MARBLE_SIMULATOR_ID          Dedicated simulator for test/snapshot/UI/audit gates
                               (required on GITHUB_ACTIONS; no shared-name lookup)
  MIGRATION_BASE_REF           Optional shipped-source migration base
  SIMULATOR_UDID               Migration simulator (defaults to MARBLE_SIMULATOR_ID)

`init` + per-gate `run` + `finalize` write one candidate run whose manifest
lists every required gate. Parallel CI jobs upload fragments; `assemble`
merges them (including the three UI shards) into one run before `finalize`.
App Store submit rejects a one-gate fragment.

Every gate retains an xcresult (or migration log) plus a teed command.log so a
step cap still names the hanging test. UI/accessibility skip sysdiagnose
collection (`-collect-test-diagnostics never`) to avoid multi-gigabyte bundles.
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

require_dedicated_simulator() {
  if [[ "${GITHUB_ACTIONS:-}" != "true" ]]; then
    return 0
  fi
  if [[ -z "${MARBLE_SIMULATOR_ID:-}" ]]; then
    echo "GITHUB_ACTIONS release gates require MARBLE_SIMULATOR_ID from scripts/release_sim.sh create." >&2
    exit 1
  fi
}

prepare_ui_simulator() {
  local simulator_id="${MARBLE_SIMULATOR_ID:-${SIMULATOR_UDID:-}}"
  if [[ -z "${simulator_id}" ]]; then
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
      echo "GITHUB_ACTIONS UI/audit gates require MARBLE_SIMULATOR_ID." >&2
      exit 1
    fi
    return 0
  fi

  # Consecutive xcodebuild invocations can leave SpringBoard busy or the device
  # shut down while Xcode finalizes the preceding result bundle. Establish one
  # deterministic ready state before launching a UI test runner.
  "${ROOT_DIR}/scripts/simctl_ready.sh" "${simulator_id}"
  xcrun simctl terminate "${simulator_id}" Prism.marbleUITests.xctrunner >/dev/null 2>&1 || true
  xcrun simctl terminate "${simulator_id}" Prism.marble >/dev/null 2>&1 || true
  sleep 2
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
      accessibility)
        if [[ ! -d "${RELEASE_EVIDENCE_RUN_DIR}/${gate}/Marble.xcresult" ]]; then
          status=failed
          exit_code=87
          printf '%s\n' "Expected ${gate} xcresult was not produced." | tee -a "${log_path}" >&2
        fi
        ;;
      ui)
        snapshot_results=("${RELEASE_EVIDENCE_RUN_DIR}/${gate}/"*.xcresult)
        if [[ ! -d "${snapshot_results[0]}" ]]; then
          status=failed
          exit_code=87
          printf '%s\n' "Expected ${gate} xcresult was not produced." | tee -a "${log_path}" >&2
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

require_commands() {
  local required
  for required in git jq ruby make; do
    command -v "${required}" >/dev/null 2>&1 || {
      echo "Required command not found: ${required}" >&2
      exit 1
    }
  done
}

parse_gates() {
  local gate seen_gates=" "
  GATES=()
  read -r -a GATES <<<"${RELEASE_EVIDENCE_GATES:-unit snapshot ui accessibility migration}"
  if (( ${#GATES[@]} == 0 )); then
    echo "RELEASE_EVIDENCE_GATES must select at least one gate." >&2
    exit 1
  fi
  for gate in "${GATES[@]}"; do
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
}

require_clean_worktree() {
  if [[ "${RELEASE_EVIDENCE_ALLOW_DIRTY:-0}" != "1" ]]; then
    if ! git -C "${ROOT_DIR}" diff --quiet --ignore-submodules -- ||
      ! git -C "${ROOT_DIR}" diff --cached --quiet --ignore-submodules -- ||
      [[ -n "$(git -C "${ROOT_DIR}" ls-files --others --exclude-standard)" ]]; then
      echo "Release evidence requires a clean worktree. Commit or remove candidate changes first." >&2
      exit 1
    fi
  fi
}

publish_continue_dir() {
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "RELEASE_EVIDENCE_CONTINUE_DIR=${RELEASE_EVIDENCE_RUN_DIR}" >>"${GITHUB_ENV}"
  fi
}

export_run_identity() {
  export RELEASE_EVIDENCE_RUN_DIR
  export RELEASE_EVIDENCE_EXPECTED_SHA="${CANDIDATE_SHA}"
  export RELEASE_EVIDENCE_EXPECTED_BUILD="${BUILD_NUMBER}"
  export RELEASE_EVIDENCE_ALLOW_DIRTY="${RELEASE_EVIDENCE_ALLOW_DIRTY:-0}"
  unset RESULT_BUNDLE_PATH
  if [[ -n "${MARBLE_SIMULATOR_ID:-}" && -z "${SIMULATOR_UDID:-}" ]]; then
    export SIMULATOR_UDID="${MARBLE_SIMULATOR_ID}"
  fi
}

create_run_dir() {
  local evidence_root requested_gates_json started_at run_stamp
  evidence_root=${RELEASE_EVIDENCE_ROOT:-"${ROOT_DIR}/TestResults/release-gates"}
  if [[ "${evidence_root}" != /* ]]; then
    echo "RELEASE_EVIDENCE_ROOT must be an absolute path: ${evidence_root}" >&2
    exit 1
  fi
  started_at=$(iso8601_now)
  run_stamp=$(date -u '+%Y%m%dT%H%M%SZ')
  requested_gates_json=$(printf '%s\n' "${GATES[@]}" | jq -R -s 'split("\n") | map(select(length > 0))')
  mkdir -p "${evidence_root}/${CANDIDATE_SHA}/build-${BUILD_NUMBER}"
  RELEASE_EVIDENCE_RUN_DIR=$(mktemp -d "${evidence_root}/${CANDIDATE_SHA}/build-${BUILD_NUMBER}/${run_stamp}.XXXXXX")
  mkdir -p "${RELEASE_EVIDENCE_RUN_DIR}/.evidence/gates"
  jq -n \
    --arg schemaVersion "1" \
    --arg startedAt "${started_at}" \
    --arg repository "${ROOT_DIR}" \
    --arg gitSha "${CANDIDATE_SHA}" \
    --arg buildNumber "${BUILD_NUMBER}" \
    --arg marketingVersion "${MARKETING_VERSION}" \
    --arg runId "$(basename "${RELEASE_EVIDENCE_RUN_DIR}")" \
    --argjson cleanRun "$([[ "${RELEASE_EVIDENCE_ALLOW_DIRTY:-0}" == "1" ]] && printf false || printf true)" \
    --argjson requestedGates "${requested_gates_json}" \
    '{schema_version: ($schemaVersion | tonumber), started_at: $startedAt,
      repository: $repository, git_sha: $gitSha, build_number: $buildNumber,
      marketing_version: $marketingVersion, run_id: $runId, clean_run: $cleanRun,
      requested_gates: $requestedGates}' \
    >"${RELEASE_EVIDENCE_RUN_DIR}/.evidence/run.json"
  export_run_identity
  publish_continue_dir
  echo "Release evidence run: ${RELEASE_EVIDENCE_RUN_DIR}"
}

load_continue_dir() {
  local run_sha run_build
  RELEASE_EVIDENCE_RUN_DIR="${RELEASE_EVIDENCE_CONTINUE_DIR}"
  if [[ "${RELEASE_EVIDENCE_RUN_DIR}" != /* ]]; then
    echo "RELEASE_EVIDENCE_CONTINUE_DIR must be an absolute path: ${RELEASE_EVIDENCE_RUN_DIR}" >&2
    exit 1
  fi
  if [[ ! -f "${RELEASE_EVIDENCE_RUN_DIR}/.evidence/run.json" ]]; then
    echo "No evidence run at ${RELEASE_EVIDENCE_RUN_DIR}" >&2
    exit 1
  fi
  run_sha=$(jq -r '.git_sha' "${RELEASE_EVIDENCE_RUN_DIR}/.evidence/run.json")
  run_build=$(jq -r '.build_number' "${RELEASE_EVIDENCE_RUN_DIR}/.evidence/run.json")
  if [[ "${run_sha}" != "${CANDIDATE_SHA}" || "${run_build}" != "${BUILD_NUMBER}" ]]; then
    echo "Continued evidence run belongs to another candidate (${run_sha} ${run_build})." >&2
    exit 1
  fi
  export_run_identity
  echo "Release evidence run: ${RELEASE_EVIDENCE_RUN_DIR}"
}

open_run_dir() {
  CANDIDATE_SHA=$(git -C "${ROOT_DIR}" rev-parse HEAD)
  BUILD_NUMBER=$(project_value CURRENT_PROJECT_VERSION)
  MARKETING_VERSION=$(project_value MARKETING_VERSION)
  require_clean_worktree
  if [[ -n "${RELEASE_EVIDENCE_CONTINUE_DIR:-}" ]]; then
    load_continue_dir
  else
    create_run_dir
  fi
}

execute_gates() {
  local gate
  OVERALL_STATUS=passed
  CANDIDATE_DRIFTED=0
  for gate in "${GATES[@]}"; do
    if [[ -f "${RELEASE_EVIDENCE_RUN_DIR}/.evidence/gates/${gate}.json" ]]; then
      echo "Refusing to overwrite release evidence gate: ${gate}" >&2
      exit 1
    fi
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
        run_gate "${gate}" env SNAPSHOT_SUITE=full SNAPSHOT_GROUPS_OVERRIDE= SNAPSHOT_SHARD_COUNT=1 SNAPSHOT_SHARD_INDEX=0 SNAPSHOT_LIST_ONLY=0 RECORD_SNAPSHOTS= SNAPSHOT_TESTING_RECORD= make -C "${ROOT_DIR}" snapshot
        ;;
      ui)
        prepare_ui_simulator
        if [[ -n "${RELEASE_EVIDENCE_UI_SHARD:-}" ]]; then
          if [[ ! "${RELEASE_EVIDENCE_UI_SHARD}" =~ ^[123]$ ]]; then
            echo "RELEASE_EVIDENCE_UI_SHARD must be 1, 2, or 3." >&2
            exit 1
          fi
          UI_ONLY_TESTING="$("${ROOT_DIR}/scripts/release_ui_shards.sh" "${RELEASE_EVIDENCE_UI_SHARD}")"
          export UI_ONLY_TESTING
          export RESULT_BUNDLE_PATH="${RELEASE_EVIDENCE_RUN_DIR}/ui/shard-${RELEASE_EVIDENCE_UI_SHARD}.xcresult"
        fi
        run_gate "${gate}" make -C "${ROOT_DIR}" ui
        unset RESULT_BUNDLE_PATH UI_ONLY_TESTING
        ;;
      accessibility)
        prepare_ui_simulator
        run_gate "${gate}" make -C "${ROOT_DIR}" audit
        ;;
      migration)
        run_gate "${gate}" make -C "${ROOT_DIR}" migration-release
        ;;
    esac
  done
}

write_manifest() {
  "${MANIFEST_TOOL}" generate "${RELEASE_EVIDENCE_RUN_DIR}"
  "${MANIFEST_TOOL}" verify "${RELEASE_EVIDENCE_RUN_DIR}/manifest.json"
  echo "Release evidence manifest: ${RELEASE_EVIDENCE_RUN_DIR}/manifest.json"
}

init_release_evidence() {
  require_commands
  if [[ -n "${RELEASE_EVIDENCE_CONTINUE_DIR:-}" ]]; then
    echo "init creates a new run; unset RELEASE_EVIDENCE_CONTINUE_DIR." >&2
    exit 1
  fi
  RELEASE_EVIDENCE_GATES="unit snapshot ui accessibility migration"
  parse_gates
  open_run_dir
}

run_release_evidence() {
  require_commands
  if [[ "${RELEASE_EVIDENCE_DEFER_MANIFEST:-0}" == "1" && -z "${RELEASE_EVIDENCE_CONTINUE_DIR:-}" ]]; then
    echo "Split gates require init (RELEASE_EVIDENCE_CONTINUE_DIR)." >&2
    exit 1
  fi
  parse_gates
  open_run_dir
  require_dedicated_simulator
  execute_gates
  if [[ "${RELEASE_EVIDENCE_DEFER_MANIFEST:-0}" == "1" ]]; then
    echo "Deferred manifest until finalize: ${RELEASE_EVIDENCE_RUN_DIR}"
    [[ "${OVERALL_STATUS}" == passed ]]
    return
  fi
  write_manifest
  [[ "${OVERALL_STATUS}" == passed ]]
}

finalize_release_evidence() {
  local gate requested
  require_commands
  if [[ -z "${RELEASE_EVIDENCE_CONTINUE_DIR:-}" ]]; then
    echo "finalize requires RELEASE_EVIDENCE_CONTINUE_DIR from init." >&2
    exit 1
  fi
  CANDIDATE_SHA=$(git -C "${ROOT_DIR}" rev-parse HEAD)
  BUILD_NUMBER=$(project_value CURRENT_PROJECT_VERSION)
  MARKETING_VERSION=$(project_value MARKETING_VERSION)
  load_continue_dir
  OVERALL_STATUS=passed
  requested=()
  while IFS= read -r gate; do
    [[ -n "${gate}" ]] || continue
    requested+=("${gate}")
  done < <(jq -r '.requested_gates[]' "${RELEASE_EVIDENCE_RUN_DIR}/.evidence/run.json")
  for gate in "${requested[@]}"; do
    if [[ ! -f "${RELEASE_EVIDENCE_RUN_DIR}/.evidence/gates/${gate}.json" ]]; then
      skip_gate "${gate}" "Skipped because the gate step did not finish."
    elif [[ "$(jq -r '.status' "${RELEASE_EVIDENCE_RUN_DIR}/.evidence/gates/${gate}.json")" != passed ]]; then
      OVERALL_STATUS=failed
    fi
  done
  write_manifest
  [[ "${OVERALL_STATUS}" == passed ]]
}

fragment_run_dirs() {
  local root="$1"
  local run_json
  [[ -d "${root}" ]] || return 0
  while IFS= read -r run_json; do
    [[ -n "${run_json}" ]] || continue
    dirname "$(dirname "${run_json}")"
  done < <(find "${root}" -path '*/.evidence/run.json' | sort)
}

copy_gate_tree() {
  local dest="$1"
  local src="$2"
  local gate="$3"
  local src_record="${src}/.evidence/gates/${gate}.json"
  local dest_record="${dest}/.evidence/gates/${gate}.json"
  [[ -f "${src_record}" ]] || return 1
  if [[ -f "${dest_record}" ]]; then
    echo "Refusing to merge duplicate release evidence gate: ${gate}" >&2
    exit 1
  fi
  mkdir -p "${dest}/${gate}"
  cp -a "${src}/${gate}/." "${dest}/${gate}/"
  cp "${src_record}" "${dest_record}"
}

merge_ui_shards() {
  local dest="$1"
  shift
  local -a shard_runs=("$@")
  local dest_ui="${dest}/ui"
  local shard run shard_dir record
  local -a records=()
  local missing=0
  mkdir -p "${dest_ui}" "${dest}/.evidence/gates"
  : >"${dest_ui}/command.log"

  for shard in 1 2 3; do
    run=""
    for shard_dir in "${shard_runs[@]}"; do
      if [[ -d "${shard_dir}/ui/shard-${shard}.xcresult" ]]; then
        run="${shard_dir}"
        break
      fi
    done
    if [[ -z "${run}" ]]; then
      printf 'Missing UI shard %s xcresult.\n' "${shard}" | tee -a "${dest_ui}/command.log" >&2
      missing=1
      continue
    fi
    cp -a "${run}/ui/shard-${shard}.xcresult" "${dest_ui}/shard-${shard}.xcresult"
    if [[ -f "${run}/ui/command.log" ]]; then
      printf '\n--- UI shard %s ---\n' "${shard}" >>"${dest_ui}/command.log"
      cat "${run}/ui/command.log" >>"${dest_ui}/command.log"
    fi
    record="${run}/.evidence/gates/ui.json"
    if [[ -f "${record}" ]]; then
      records+=("${record}")
    fi
  done

  if (( missing != 0 || ${#records[@]} != 3 )); then
    write_gate_record ui failed 1 "$(iso8601_now)" "$(iso8601_now)" \
      "assemble ui shards 1 2 3" \
      "Expected UI shards 1, 2 and 3; one or more fragments were missing."
    OVERALL_STATUS=failed
    return
  fi

  jq -s '{
      name: "ui",
      status: (if all(.status == "passed") then "passed" else "failed" end),
      exit_code: (map(.exit_code) | max),
      started_at: (map(.started_at) | min),
      completed_at: (map(.completed_at) | max),
      command: (map(.command) | join(" ; ")),
      reason: (map(.reason) | map(select(. != null)) | if length == 0 then null else join("; ") end)
    }' "${records[@]}" >"${dest}/.evidence/gates/ui.json"
  if [[ "$(jq -r '.status' "${dest}/.evidence/gates/ui.json")" != passed ]]; then
    OVERALL_STATUS=failed
  fi
}

assemble_release_evidence() {
  local fragment_root="$1"
  local run_dir gate run_sha run_build
  local -a ui_runs=()
  require_commands
  if [[ -z "${fragment_root}" || "${fragment_root}" != /* ]]; then
    echo "assemble requires an absolute fragment directory." >&2
    exit 1
  fi
  if [[ -n "${RELEASE_EVIDENCE_CONTINUE_DIR:-}" ]]; then
    echo "assemble creates a new run; unset RELEASE_EVIDENCE_CONTINUE_DIR." >&2
    exit 1
  fi
  RELEASE_EVIDENCE_GATES="unit snapshot ui accessibility migration"
  parse_gates
  open_run_dir
  OVERALL_STATUS=passed

  while IFS= read -r run_dir; do
    [[ -n "${run_dir}" ]] || continue
    run_sha=$(jq -r '.git_sha' "${run_dir}/.evidence/run.json")
    run_build=$(jq -r '.build_number' "${run_dir}/.evidence/run.json")
    if [[ "${run_sha}" != "${CANDIDATE_SHA}" || "${run_build}" != "${BUILD_NUMBER}" ]]; then
      echo "Fragment ${run_dir} belongs to another candidate (${run_sha} ${run_build})." >&2
      exit 1
    fi
    if [[ -d "${run_dir}/ui" ]]; then
      ui_runs+=("${run_dir}")
      continue
    fi
    for gate in unit snapshot accessibility migration; do
      if [[ -f "${run_dir}/.evidence/gates/${gate}.json" ]]; then
        copy_gate_tree "${RELEASE_EVIDENCE_RUN_DIR}" "${run_dir}" "${gate}"
      fi
    done
  done < <(fragment_run_dirs "${fragment_root}")

  if (( ${#ui_runs[@]} > 0 )); then
    merge_ui_shards "${RELEASE_EVIDENCE_RUN_DIR}" "${ui_runs[@]}"
  fi

  export RELEASE_EVIDENCE_CONTINUE_DIR="${RELEASE_EVIDENCE_RUN_DIR}"
  publish_continue_dir
  echo "Assembled release evidence run: ${RELEASE_EVIDENCE_RUN_DIR}"
}

case "${1:-}" in
  init)
    init_release_evidence
    ;;
  run)
    run_release_evidence
    ;;
  assemble)
    [[ $# -eq 2 ]] || { usage >&2; exit 1; }
    assemble_release_evidence "$2"
    ;;
  finalize)
    finalize_release_evidence
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
