#!/usr/bin/env bash
# Shared constants and helpers for Marble cloud / CI release scripts.
# Sourced by other scripts; do not execute directly.

MARBLE_ASC_APP_ID="${ASC_APP:-${ASC_APP_ID:-6757725234}}"
MARBLE_ASC_BUNDLE_ID="${ASC_BUNDLE_ID:-Prism.marble}"
MARBLE_WIDGET_BUNDLE_ID="${ASC_WIDGET_BUNDLE_ID:-Prism.marble.MarbleWidgets}"
MARBLE_TEAM_ID="${ASC_TEAM_ID:-L49MKXGVM4}"
MARBLE_PLATFORM="${ASC_PLATFORM:-IOS}"
MARBLE_SCHEME="${SCHEME:-marble}"
MARBLE_PROJECT="${PROJECT:-marble.xcodeproj}"

# Pinned App Store profiles (names are load-bearing: they match
# .asc/ExportOptions.plist and the Release PROVISIONING_PROFILE_SPECIFIER
# values in marble.xcodeproj). IDs are the last known ASC profile ids from
# RELEASE_HANDOFF.md (build 48 signing refresh). Download-by-name is preferred;
# IDs are a fallback if the list endpoint is noisy.
MARBLE_APP_PROFILE_NAME="${MARBLE_APP_PROFILE_NAME:-Prism marble App Store build 48 2026-07-24}"
MARBLE_WIDGET_PROFILE_NAME="${MARBLE_WIDGET_PROFILE_NAME:-Prism marble MarbleWidgets App Store build 48 2026-07-24}"
MARBLE_APP_PROFILE_ID="${MARBLE_APP_PROFILE_ID:-G545NTS973}"
MARBLE_WIDGET_PROFILE_ID="${MARBLE_WIDGET_PROFILE_ID:-JF52GQ2SSV}"

MARBLE_GITHUB_OWNER="${MARBLE_GITHUB_OWNER:-enzo-prism}"
MARBLE_GITHUB_REPO="${MARBLE_GITHUB_REPO:-marble}"
MARBLE_GITHUB_SLUG="${MARBLE_GITHUB_OWNER}/${MARBLE_GITHUB_REPO}"

_MARBLE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARBLE_ROOT="$(cd "${_MARBLE_LIB_DIR}/../.." && pwd)"

# asc's Linux installer drops the binary in ~/.local/bin, which is often
# missing from non-login Cloud Agent shells.
export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"

marble_repo_root() {
  echo "$MARBLE_ROOT"
}

marble_require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command not found: $cmd" >&2
    return 1
  fi
}

marble_is_macos() {
  [[ "$(uname -s)" == "Darwin" ]]
}

marble_is_linux() {
  [[ "$(uname -s)" == "Linux" ]]
}

marble_pbx_value() {
  local key="$1"
  local root="$2"
  if [[ -z "$root" ]]; then
    root="$(marble_repo_root)"
  fi
  local pbx="${root}/${MARBLE_PROJECT}/project.pbxproj"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$pbx" "$key" <<'PY'
import re, sys
path, key = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
vals = list(dict.fromkeys(re.findall(rf"{re.escape(key)} = ([^;]+);", text)))
if not vals:
    sys.exit(1)
sys.stdout.write(vals[0].strip())
PY
    return
  fi
  if command -v ruby >/dev/null 2>&1; then
    ruby -e '
      project = File.read(ARGV[0])
      key = ARGV[1]
      versions = project.scan(/#{Regexp.escape(key)} = ([^;]+);/).flatten.map(&:strip).uniq
      abort("not found") if versions.empty?
      print versions.first
    ' "$pbx" "$key"
    return
  fi
  echo "error: python3 or ruby required to read ${key} from project.pbxproj" >&2
  return 1
}

marble_marketing_version() {
  marble_pbx_value MARKETING_VERSION "${1:-}"
}

marble_project_build() {
  marble_pbx_value CURRENT_PROJECT_VERSION "${1:-}"
}

marble_asc_env_ready() {
  [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]] || return 1
  [[ -n "${ASC_PRIVATE_KEY_B64:-}" || -n "${ASC_PRIVATE_KEY:-}" || -n "${ASC_PRIVATE_KEY_PATH:-}" ]]
}

marble_export_asc_ci() {
  export ASC_APP_ID="${MARBLE_ASC_APP_ID}"
  export ASC_APP="${MARBLE_ASC_APP_ID}"
  export ASC_BYPASS_KEYCHAIN="${ASC_BYPASS_KEYCHAIN:-true}"
  export ASC_DEFAULT_OUTPUT="${ASC_DEFAULT_OUTPUT:-json}"
  export ASC_UPLOAD_TIMEOUT="${ASC_UPLOAD_TIMEOUT:-45m}"
}

# GitHub token usable for Actions API. Prefer GITHUB_TOKEN / GH_TOKEN, then
# the x-access-token embedded in origin (cloud-agent git credential).
marble_github_token() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    printf '%s' "$GITHUB_TOKEN"
    return 0
  fi
  if [[ -n "${GH_TOKEN:-}" ]]; then
    printf '%s' "$GH_TOKEN"
    return 0
  fi
  local url
  url="$(git remote get-url origin 2>/dev/null || true)"
  if [[ "$url" =~ x-access-token:([^@]+)@github.com ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

marble_github_api() {
  local method="$1"
  local path="$2"
  shift 2
  local token
  token="$(marble_github_token)" || {
    echo "error: no GitHub token available" >&2
    return 1
  }
  curl -sS -X "$method" \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${MARBLE_GITHUB_SLUG}${path}" \
    "$@"
}

marble_unique_publish_tag() {
  local kind="$1"
  local extra="${2:-}"
  local ts sha
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  sha="$(git rev-parse --short HEAD)"
  if [[ -n "$extra" ]]; then
    echo "publish/${kind}/${extra}/${ts}-${sha}"
  else
    echo "publish/${kind}/${ts}-${sha}"
  fi
}

marble_secret_present() {
  local name="$1"
  local value="${!name:-}"
  [[ -n "$value" ]]
}

marble_json_first() {
  # Usage: marble_json_first '.path' <<< "$json"
  jq -er "$1"
}
