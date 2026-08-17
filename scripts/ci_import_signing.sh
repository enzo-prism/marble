#!/usr/bin/env bash
# Import Apple Distribution identity + App Store provisioning profiles on a
# GitHub-hosted macOS runner. Profiles are downloaded via the ASC API (pinned
# by name); the distribution *private* key cannot be fetched from Apple and
# must arrive as APPLE_DISTRIBUTION_P12_B64.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/marble_release.sh
source "${SCRIPT_DIR}/lib/marble_release.sh"

marble_export_asc_ci

if ! marble_is_macos; then
  echo "error: ci_import_signing.sh must run on macOS" >&2
  exit 1
fi

if [[ -z "${APPLE_DISTRIBUTION_P12_B64:-}" ]]; then
  echo "error: APPLE_DISTRIBUTION_P12_B64 is not set" >&2
  echo "Export the Apple Distribution certificate (build 48 cert 9M47KCWLU8) as a .p12 on a Mac," >&2
  echo "then store base64 of that file as the GitHub Actions secret APPLE_DISTRIBUTION_P12_B64." >&2
  exit 1
fi

if [[ -z "${APPLE_DISTRIBUTION_P12_PASSWORD:-}" ]]; then
  echo "error: APPLE_DISTRIBUTION_P12_PASSWORD is not set" >&2
  exit 1
fi

RUNNER_TEMP="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
KEYCHAIN_PATH="${RUNNER_TEMP}/marble-signing.keychain-db"
KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-$(openssl rand -base64 24)}"
P12_PATH="${RUNNER_TEMP}/apple-distribution.p12"
SIGNING_DIR="${RUNNER_TEMP}/marble-signing"
PROFILES_DIR_LEGACY="${HOME}/Library/MobileDevice/Provisioning Profiles"
PROFILES_DIR_XCODE="${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"

cleanup_tmp() {
  rm -f "$P12_PATH"
}
trap cleanup_tmp EXIT

mkdir -p "$SIGNING_DIR" "$PROFILES_DIR_LEGACY" "$PROFILES_DIR_XCODE"

echo "Creating ephemeral signing keychain"
security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db

echo "Importing Apple Distribution .p12"
echo "$APPLE_DISTRIBUTION_P12_B64" | base64 --decode > "$P12_PATH"
security import "$P12_PATH" \
  -k "$KEYCHAIN_PATH" \
  -P "$APPLE_DISTRIBUTION_P12_PASSWORD" \
  -A \
  -t cert \
  -f pkcs12 \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -T /usr/bin/productbuild

security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH" >/dev/null

install_profile_file() {
  local src="$1"
  local dest_name
  dest_name="$(basename "$src")"
  cp "$src" "${PROFILES_DIR_LEGACY}/${dest_name}"
  cp "$src" "${PROFILES_DIR_XCODE}/${dest_name}"
  echo "Installed provisioning profile $(basename "$src")"
}

decode_optional_profile() {
  local b64="$1"
  local dest="$2"
  if [[ -z "$b64" ]]; then
    return 1
  fi
  echo "$b64" | base64 --decode > "$dest"
  install_profile_file "$dest"
}

download_profile() {
  local name="$1"
  local fallback_id="$2"
  local dest="$3"
  local id=""

  if marble_require_cmd asc && marble_asc_env_ready; then
    local list_json
    list_json="$(asc profiles list --profile-type IOS_APP_STORE --output json --pretty || true)"
    if [[ -n "$list_json" ]]; then
      id="$(printf '%s' "$list_json" | jq -r --arg name "$name" '
        (.data // .)
        | if type=="array" then . else (.data // []) end
        | .[]
        | select((.attributes.name // .name // "") == $name)
        | (.id // empty)
      ' | head -n 1 || true)"
    fi
    if [[ -z "$id" ]]; then
      id="$fallback_id"
    fi
    echo "Downloading profile ${name} (${id})"
    if asc profiles download --id "$id" --output "$dest"; then
      install_profile_file "$dest"
      return 0
    fi
    echo "warning: asc profiles download failed for ${name} (${id})" >&2
  fi
  return 1
}

echo "Installing App Store provisioning profiles"
app_ok=0
widget_ok=0

if decode_optional_profile "${MOBILEPROVISION_APP_B64:-}" "${SIGNING_DIR}/app.mobileprovision"; then
  app_ok=1
elif download_profile "$MARBLE_APP_PROFILE_NAME" "$MARBLE_APP_PROFILE_ID" "${SIGNING_DIR}/app.mobileprovision"; then
  app_ok=1
fi

if decode_optional_profile "${MOBILEPROVISION_WIDGET_B64:-}" "${SIGNING_DIR}/widget.mobileprovision"; then
  widget_ok=1
elif download_profile "$MARBLE_WIDGET_PROFILE_NAME" "$MARBLE_WIDGET_PROFILE_ID" "${SIGNING_DIR}/widget.mobileprovision"; then
  widget_ok=1
fi

if [[ "$app_ok" -ne 1 || "$widget_ok" -ne 1 ]]; then
  echo "error: could not install both App Store profiles" >&2
  echo "Need ${MARBLE_APP_PROFILE_NAME} and ${MARBLE_WIDGET_PROFILE_NAME}." >&2
  echo "Either make ASC API credentials available, or set MOBILEPROVISION_APP_B64 and MOBILEPROVISION_WIDGET_B64." >&2
  exit 1
fi

echo "Signing identity in keychain:"
security find-identity -v -p codesigning "$KEYCHAIN_PATH" || true
echo "Signing import complete"
