#!/usr/bin/env bash
# App Store Connect API mutations that do not need Xcode. Safe to run on
# Linux Cloud Agents *and* on GitHub-hosted ubuntu runners.
#
# Usage:
#   scripts/ci_appstore.sh validate [--version 2.3]
#   scripts/ci_appstore.sh stage --version 2.3 [--build BUILD_ID]
#   scripts/ci_appstore.sh submit --version 2.3 [--build BUILD_ID] --confirm
#   scripts/ci_appstore.sh release --version 2.2 --confirm
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/marble_release.sh
source "${SCRIPT_DIR}/lib/marble_release.sh"

ROOT="$(marble_repo_root)"
cd "$ROOT"

ACTION="${1:-}"
shift || true

VERSION=""
BUILD_ID=""
CONFIRM=0
DRY_RUN=0

if [[ -z "$ACTION" ]]; then
  echo "usage: $0 {validate|status|stage|submit|release} [--version X] [--build ID] [--confirm] [--dry-run]" >&2
  exit 2
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --build) BUILD_ID="${2:-}"; shift 2 ;;
    --confirm) CONFIRM=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

marble_require_cmd asc
marble_require_cmd jq
marble_export_asc_ci

if ! marble_asc_env_ready; then
  echo "error: ASC_KEY_ID, ASC_ISSUER_ID, and ASC_PRIVATE_KEY_B64 (or PATH/PEM) are required" >&2
  exit 1
fi

if [[ -z "$VERSION" ]]; then
  VERSION="$(marble_marketing_version "$ROOT")"
fi

stage_version() {
  local metadata_dir="$ROOT/AppStore/metadata/version/$VERSION"
  [[ -d "$metadata_dir" ]] || { echo "error: missing tracked version metadata: $metadata_dir" >&2; return 1; }
  asc release stage --app "$MARBLE_ASC_APP_ID" --version "$VERSION" --build-id "$BUILD_ID" \
    --metadata-dir "$metadata_dir" --platform "$MARBLE_PLATFORM" --strict-validate "$@"
}

require_confirm() {
  if [[ "$CONFIRM" -ne 1 ]]; then
    echo "error: ${ACTION} is a production mutation; pass --confirm" >&2
    exit 1
  fi
  if [[ "$DRY_RUN" -eq 0 ]]; then
    ruby "${ROOT}/scripts/verify_release_candidate.rb" "${RELEASE_EVIDENCE_MANIFEST:-}" "$ROOT" "$VERSION"
  fi
}

version_record() {
  local json
  json="$(asc versions list --app "$MARBLE_ASC_APP_ID" --version "$VERSION" --platform "$MARBLE_PLATFORM" --output json)"
  printf '%s' "$json" | jq -e --arg v "$VERSION" '
    (.data // [])
    | map(select((.attributes.versionString // .attributes.version // "") == $v))
    | .[0]
  '
}


verify_build_identity() {
  local build_json build_number expected train_builds
  local receipt_build_id
  receipt_build_id="$(jq -er '.build_id' "${RELEASE_UPLOAD_RECEIPT}")"
  [[ "$1" == "$receipt_build_id" ]] || { echo "error: ASC build differs from the source-verified upload receipt" >&2; exit 1; }
  expected="$(marble_project_build "$ROOT")"
  build_json="$(asc builds info --build-id "$1" --output json)"
  build_number="$(printf '%s' "$build_json" | jq -r '.data.attributes.version // .attributes.version // .buildNumber // empty')"
  if [[ "$build_number" != "$expected" ]]; then
    echo "error: App Store build does not match verified candidate ${expected}" >&2
    exit 1
  fi
  ruby "${ROOT}/scripts/asc_build_status.rb" --app "$MARBLE_ASC_APP_ID" --version "$VERSION" --platform "$MARBLE_PLATFORM" --build "$1" --build-number "$expected" --validate
  train_builds="$(asc builds list --app "$MARBLE_ASC_APP_ID" --version "$VERSION" --build-number "$expected" --output json)"
  printf '%s' "$train_builds" | jq -e --arg id "$1" '.data | any(.id == $id)' >/dev/null || {
    echo "error: build does not belong to this app and version" >&2
    exit 1
  }
}

print_status() {
  local selector=(--build-number "$(marble_project_build "$ROOT")")
  [[ -z "$BUILD_ID" ]] || selector=(--build "$BUILD_ID")
  ruby "${ROOT}/scripts/asc_build_status.rb" --app "$MARBLE_ASC_APP_ID" --version "$VERSION" --platform "$MARBLE_PLATFORM" "${selector[@]}"
  asc versions list --app "$MARBLE_ASC_APP_ID" --platform "$MARBLE_PLATFORM" --output table
}

validate_appstore() {
  asc validate --app "$MARBLE_ASC_APP_ID" --version "$VERSION" --platform "$MARBLE_PLATFORM" --strict --output table
}

case "$ACTION" in
  validate)
    validate_appstore
    ;;
  status)
    print_status
    echo "=== builds ==="
    asc builds list --app "$MARBLE_ASC_APP_ID" --sort -uploadedDate --limit 10 --output table || true
    echo "=== versions ==="
    asc versions list --app "$MARBLE_ASC_APP_ID" --platform "$MARBLE_PLATFORM" --output table || true
    ;;
  stage)
    require_confirm
    if [[ -z "$BUILD_ID" ]]; then
      echo "error: --build must identify the exact verified ASC build" >&2
      exit 1
    fi
    echo "Staging ${VERSION} with build ${BUILD_ID}"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      stage_version --dry-run
      exit 0
    fi
    verify_build_identity "$BUILD_ID"
    stage_version --dry-run
    stage_version --confirm
    ;;
  submit)
    require_confirm
    if [[ -z "$BUILD_ID" ]]; then
      echo "error: --build must identify the exact verified ASC build" >&2
      exit 1
    fi
    echo "Submitting ${VERSION} (build ${BUILD_ID}) for App Review"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      stage_version --dry-run
      echo "dry-run: skipping review submission"
      exit 0
    fi
    verify_build_identity "$BUILD_ID"
    stage_version --dry-run
    stage_version --confirm

    local_version_json="$(version_record || true)"
    version_id="$(printf '%s' "$local_version_json" | jq -r '.id // empty')"
    if [[ -z "$version_id" ]]; then
      echo "error: could not resolve App Store version id for ${VERSION}" >&2
      exit 1
    fi

    validate_appstore

    source "${SCRIPT_DIR}/lib/review_submission.sh"
    submission_id="$(marble_review_submission_id "$MARBLE_ASC_APP_ID" "$MARBLE_PLATFORM" "$version_id")"
    asc review submissions-submit --id "$submission_id" --confirm
    echo "Submitted. submission_id=${submission_id} version_id=${version_id} build_id=${BUILD_ID}"
    asc submit status --version-id "$version_id" --output table || true
    ;;
  release)
    require_confirm
    local_version_json="$(version_record)"
    version_id="$(printf '%s' "$local_version_json" | jq -r '.id // empty')"
    state="$(printf '%s' "$local_version_json" | jq -r '.attributes.appStoreState // .attributes.state // empty')"
    echo "Version ${VERSION} id=${version_id} state=${state}"
    if [[ -z "$version_id" ]]; then
      echo "error: no App Store version ${VERSION}" >&2
      exit 1
    fi
    if [[ "$state" != "PENDING_DEVELOPER_RELEASE" && "$state" != "READY_FOR_DISTRIBUTION" ]]; then
      echo "warning: state is ${state}; Apple only releases PENDING_DEVELOPER_RELEASE / approved manual-release versions" >&2
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "dry-run: would run asc versions release --version-id ${version_id} --confirm"
      exit 0
    fi
    attached_json="$(asc versions view --version-id "$version_id" --include-build --output json)"
    attached_id="$(printf '%s' "$attached_json" | jq -r '.buildId // .build.id // .data.relationships.build.data.id // empty')"
    [[ -n "$attached_id" ]] || { echo "error: version has no attached build" >&2; exit 1; }
    verify_build_identity "$attached_id"
    asc versions release --version-id "$version_id" --confirm
    echo "Release requested for ${VERSION} (${version_id})"
    asc versions view --version-id "$version_id" --output table || true
    ;;
  *)
    echo "usage: $0 {validate|status|stage|submit|release} [--version X] [--build ID] [--confirm] [--dry-run]" >&2
    exit 2
    ;;
esac
