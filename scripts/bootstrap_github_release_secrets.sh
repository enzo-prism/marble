#!/usr/bin/env bash
# One-time bootstrap: run on the Mac that already archives Marble.
# Encodes the Apple Distribution .p12 + (optional) profiles and writes them
# as GitHub Actions secrets via `gh secret set`.
#
# Required env:
#   P12_PATH                 path to Apple Distribution .p12 (cert 9M47KCWLU8)
#   P12_PASSWORD             password for that .p12
#   ASC_KEY_ID               App Store Connect API key id
#   ASC_ISSUER_ID            App Store Connect issuer id
#   ASC_P8_PATH              path to AuthKey_XXXX.p8
#
# Optional env:
#   APP_PROFILE_PATH         .mobileprovision for Prism.marble
#   WIDGET_PROFILE_PATH      .mobileprovision for Prism.marble.MarbleWidgets
#   GITHUB_REPO              default enzo-prism/marble
set -euo pipefail

REPO="${GITHUB_REPO:-enzo-prism/marble}"

need() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "error: set ${name}" >&2
    exit 1
  fi
}

need P12_PATH
need P12_PASSWORD
need ASC_KEY_ID
need ASC_ISSUER_ID
need ASC_P8_PATH

if [[ ! -f "$P12_PATH" ]]; then echo "error: P12_PATH not a file: $P12_PATH" >&2; exit 1; fi
if [[ ! -f "$ASC_P8_PATH" ]]; then echo "error: ASC_P8_PATH not a file: $ASC_P8_PATH" >&2; exit 1; fi
if ! command -v gh >/dev/null 2>&1; then echo "error: gh CLI is required" >&2; exit 1; fi

b64_file() {
  if base64 -w0 /dev/null >/dev/null 2>&1; then
    base64 -w0 "$1"
  else
    base64 < "$1" | tr -d '\n'
  fi
}

echo "Writing GitHub Actions secrets on ${REPO}"

gh secret set ASC_KEY_ID --repo "$REPO" --body "$ASC_KEY_ID"
gh secret set ASC_ISSUER_ID --repo "$REPO" --body "$ASC_ISSUER_ID"
gh secret set ASC_PRIVATE_KEY_B64 --repo "$REPO" --body "$(b64_file "$ASC_P8_PATH")"
gh secret set APPLE_DISTRIBUTION_P12_B64 --repo "$REPO" --body "$(b64_file "$P12_PATH")"
gh secret set APPLE_DISTRIBUTION_P12_PASSWORD --repo "$REPO" --body "$P12_PASSWORD"

if [[ -n "${APP_PROFILE_PATH:-}" ]]; then
  gh secret set MOBILEPROVISION_APP_B64 --repo "$REPO" --body "$(b64_file "$APP_PROFILE_PATH")"
fi
if [[ -n "${WIDGET_PROFILE_PATH:-}" ]]; then
  gh secret set MOBILEPROVISION_WIDGET_B64 --repo "$REPO" --body "$(b64_file "$WIDGET_PROFILE_PATH")"
fi

echo "Done. Confirm with: gh secret list --repo ${REPO}"
echo
echo "Also paste the same ASC_KEY_ID / ASC_ISSUER_ID / ASC_PRIVATE_KEY_B64 into"
echo "Cursor Cloud Agents → Secrets so Linux agents can run API-only commands."
