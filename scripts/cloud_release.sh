#!/usr/bin/env bash
# Cloud-agent entrypoint for TestFlight and App Store.
#
# Linux agents cannot archive. They:
#   1. Run API-only ASC commands when ASC_* secrets are present
#   2. Dispatch (or tag-push) the macos-26 GitHub Actions jobs for binaries
#
# Usage:
#   scripts/cloud_release.sh preflight
#   scripts/cloud_release.sh status
#   scripts/cloud_release.sh testflight [--dry-run] [--no-wait]
#   scripts/cloud_release.sh appstore-validate [--version 2.3]
#   scripts/cloud_release.sh appstore-submit --version 2.3 --confirm
#   scripts/cloud_release.sh appstore-release --version 2.2 --confirm
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/marble_release.sh
source "${SCRIPT_DIR}/lib/marble_release.sh"

ROOT="$(marble_repo_root)"
cd "$ROOT"

COMMAND="${1:-}"
shift || true

DRY_RUN=0
WAIT=1
CONFIRM=0
VERSION=""
BUILD_ID=""
NO_WATCH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --no-wait) WAIT=0; shift ;;
    --no-watch) NO_WATCH=1; shift ;;
    --confirm) CONFIRM=1; shift ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    --build) BUILD_ID="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$COMMAND" ]]; then
  echo "usage: $0 {preflight|status|testflight|appstore-validate|appstore-submit|appstore-release} [options]" >&2
  exit 2
fi

if [[ -z "$VERSION" ]]; then
  VERSION="$(marble_marketing_version "$ROOT")"
fi

print_secret_status() {
  local name="$1"
  if marble_secret_present "$name"; then
    printf '  %-32s present\n' "$name"
  else
    printf '  %-32s MISSING\n' "$name"
  fi
}

preflight() {
  echo "Marble cloud release preflight"
  echo "host: $(uname -s) $(uname -m)"
  echo "repo: ${MARBLE_GITHUB_SLUG}"
  echo "local version: ${VERSION} ($(marble_project_build "$ROOT"))"
  echo
  echo "CLIs:"
  printf '  %-12s %s\n' "asc" "$(command -v asc >/dev/null && asc --version 2>/dev/null || echo MISSING)"
  printf '  %-12s %s\n' "gh" "$(command -v gh >/dev/null && gh --version | head -n 1 || echo MISSING)"
  printf '  %-12s %s\n' "jq" "$(command -v jq >/dev/null && jq --version || echo MISSING)"
  printf '  %-12s %s\n' "xcodebuild" "$(command -v xcodebuild >/dev/null && xcodebuild -version 2>/dev/null | head -n 1 || echo 'not on this VM (expected on Linux)')"
  echo
  echo "Cursor / process secrets (API path):"
  print_secret_status ASC_KEY_ID
  print_secret_status ASC_ISSUER_ID
  print_secret_status ASC_PRIVATE_KEY_B64
  print_secret_status ASC_PRIVATE_KEY
  print_secret_status ASC_PRIVATE_KEY_PATH
  echo
  if marble_asc_env_ready; then
    echo "ASC API: credentials detected. Running auth status..."
    marble_export_asc_ci
    asc auth status --validate --output json --pretty || echo "warning: asc auth status failed"
  else
    echo "ASC API: no credentials in this environment."
    echo "Add ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_B64 to the Cursor Cloud Agents Secrets tab."
  fi
  echo
  echo "GitHub Actions dispatch:"
  if marble_github_token >/dev/null; then
    echo "  git/GitHub token: present"
    local wf
    wf="$(marble_github_api GET /actions/workflows 2>/dev/null || true)"
    if printf '%s' "$wf" | jq -e '.workflows' >/dev/null 2>&1; then
      printf '%s' "$wf" | jq -r '.workflows[] | "  workflow: \(.name) (\(.path)) \(.state)"'
    else
      echo "  warning: could not list workflows via API (token may be contents-only)."
      echo "  Binary publishes will use git tag push: publish/testflight/<timestamp>-<sha>"
    fi
  else
    echo "  no GitHub token; tag push may still work via origin"
  fi
  echo
  echo "See CLOUD_RELEASE.md for the one-time GitHub Actions secret bootstrap."
}

watch_workflow() {
  local workflow_file="$1"
  local sha="$2"
  if [[ "$NO_WATCH" -eq 1 || "$WAIT" -eq 0 ]]; then
    echo "Not watching the GitHub Actions run. Track it at https://github.com/${MARBLE_GITHUB_SLUG}/actions"
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    echo "gh not installed; open https://github.com/${MARBLE_GITHUB_SLUG}/actions"
    return 0
  fi
  echo "Waiting for workflow ${workflow_file} on ${sha}..."
  local i run_id
  for i in $(seq 1 30); do
    run_id="$(gh run list --repo "$MARBLE_GITHUB_SLUG" --workflow "$workflow_file" --limit 10 \
      --json databaseId,headSha,status \
      --jq ".[] | select(.headSha==\"${sha}\") | .databaseId" 2>/dev/null | head -n 1 || true)"
    if [[ -n "$run_id" ]]; then
      gh run watch "$run_id" --repo "$MARBLE_GITHUB_SLUG" --exit-status || {
        echo "warning: gh run watch failed (token may lack actions:read). Open the Actions tab." >&2
        return 0
      }
      return 0
    fi
    sleep 4
  done
  echo "Timed out waiting for the Actions run to appear. Open https://github.com/${MARBLE_GITHUB_SLUG}/actions"
}

dispatch_or_tag() {
  local workflow_file="$1"
  local event_inputs_json="$2"
  local tag="$3"
  local sha
  sha="$(git rev-parse HEAD)"

  echo "Attempting workflow_dispatch for ${workflow_file}"
  local branch body
  branch="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
  if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
    echo "Detached HEAD: skipping workflow_dispatch (needs a branch/tag name), using git tag"
    branch=""
  fi
  body="$(jq -n --arg ref "$branch" --argjson inputs "$event_inputs_json" \
    '{ref: $ref, inputs: $inputs}')"

  local tmp status
  tmp="$(mktemp)"
  status="000"
  if [[ -n "$branch" ]]; then
    set +e
    marble_github_api POST "/actions/workflows/${workflow_file}/dispatches" \
      -H "Content-Type: application/json" \
      -d "$body" \
      -o "$tmp" \
      -w "%{http_code}" > "${tmp}.code"
    status="$(cat "${tmp}.code")"
    set -e
    rm -f "${tmp}.code"
  fi

  if [[ "$status" == "204" ]]; then
    echo "workflow_dispatch accepted (${workflow_file})"
    rm -f "$tmp"
    watch_workflow "$workflow_file" "$sha"
    return 0
  fi

  if [[ "$status" != "000" ]]; then
    echo "workflow_dispatch returned HTTP ${status}; falling back to git tag ${tag}"
    if [[ -s "$tmp" ]]; then
      head -c 500 "$tmp"; echo
    fi
  fi
  rm -f "$tmp"

  if git rev-parse "$tag" >/dev/null 2>&1; then
    echo "error: tag ${tag} already exists locally" >&2
    exit 1
  fi
  git tag -a "$tag" -m "Cloud agent publish: ${workflow_file}"
  git push origin "refs/tags/${tag}"
  echo "Pushed tag ${tag}. GitHub Actions should start from the tag."
  watch_workflow "$workflow_file" "$sha"
}

run_local_api() {
  local args=("$@")
  if ! marble_asc_env_ready; then
    echo "error: ASC API credentials are not available in this environment" >&2
    echo "Add ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_B64 to Cursor Cloud Agent secrets," >&2
    echo "or dispatch the GitHub Actions App Store workflow (which uses Actions secrets)." >&2
    return 1
  fi
  marble_export_asc_ci
  "${SCRIPT_DIR}/ci_appstore.sh" "${args[@]}"
}

case "$COMMAND" in
  preflight)
    preflight
    ;;
  status)
    if marble_asc_env_ready; then
      run_local_api status --version "$VERSION"
    else
      echo "No ASC credentials here. Showing GitHub Actions recent runs instead."
      gh run list --repo "$MARBLE_GITHUB_SLUG" --limit 10 || true
    fi
    ;;
  testflight)
    if marble_is_macos && command -v xcodebuild >/dev/null 2>&1 && marble_asc_env_ready; then
      echo "macOS + Xcode + ASC credentials: running local staged TestFlight publish"
      extra=()
      [[ "$DRY_RUN" -eq 1 ]] && extra+=(--dry-run)
      [[ "$WAIT" -eq 0 ]] && extra+=(--no-wait)
      "${SCRIPT_DIR}/ci_testflight.sh" "${extra[@]}"
      exit 0
    fi
    echo "Linux / no Xcode: dispatching GitHub Actions macos-26 TestFlight job"
    inputs="$(jq -n \
      --arg confirm "publish" \
      --argjson dry_run "$([[ "$DRY_RUN" -eq 1 ]] && echo true || echo false)" \
      '{confirm: $confirm, dry_run: $dry_run}')"
    tag="$(marble_unique_publish_tag testflight)"
    dispatch_or_tag "release-testflight.yml" "$inputs" "$tag"
    ;;
  appstore-validate)
    if marble_asc_env_ready; then
      run_local_api validate --version "$VERSION"
    else
      inputs="$(jq -n --arg version "$VERSION" --argjson dry_run "$([[ "$DRY_RUN" -eq 1 ]] && echo true || echo false)" \
        '{action: "validate", version: $version, confirm: "no", dry_run: $dry_run}')"
      tag="$(marble_unique_publish_tag appstore-validate "$VERSION")"
      dispatch_or_tag "release-appstore.yml" "$inputs" "$tag"
    fi
    ;;
  appstore-submit)
    if [[ "$CONFIRM" -ne 1 ]]; then
      echo "error: App Store submit requires --confirm (explicit user approval)" >&2
      exit 1
    fi
    if marble_asc_env_ready; then
      extra=(submit --version "$VERSION" --confirm)
      [[ -n "$BUILD_ID" ]] && extra+=(--build "$BUILD_ID")
      [[ "$DRY_RUN" -eq 1 ]] && extra+=(--dry-run)
      run_local_api "${extra[@]}"
    else
      inputs="$(jq -n --arg version "$VERSION" --arg build "$BUILD_ID" --argjson dry_run "$([[ "$DRY_RUN" -eq 1 ]] && echo true || echo false)" \
        '{action: "submit", version: $version, build_id: $build, confirm: "submit", dry_run: $dry_run}')"
      tag="$(marble_unique_publish_tag appstore-submit "$VERSION")"
      dispatch_or_tag "release-appstore.yml" "$inputs" "$tag"
    fi
    ;;
  appstore-release)
    if [[ "$CONFIRM" -ne 1 ]]; then
      echo "error: App Store release requires --confirm (explicit user approval)" >&2
      exit 1
    fi
    if marble_asc_env_ready; then
      extra=(release --version "$VERSION" --confirm)
      [[ "$DRY_RUN" -eq 1 ]] && extra+=(--dry-run)
      run_local_api "${extra[@]}"
    else
      inputs="$(jq -n --arg version "$VERSION" --argjson dry_run "$([[ "$DRY_RUN" -eq 1 ]] && echo true || echo false)" \
        '{action: "release", version: $version, confirm: "release", dry_run: $dry_run}')"
      tag="$(marble_unique_publish_tag appstore-release "$VERSION")"
      dispatch_or_tag "release-appstore.yml" "$inputs" "$tag"
    fi
    ;;
  *)
    echo "usage: $0 {preflight|status|testflight|appstore-validate|appstore-submit|appstore-release} [options]" >&2
    exit 2
    ;;
esac
