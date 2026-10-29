#!/usr/bin/env bash
# Source from a set -euo pipefail caller. Echoes the verified draft ID only.
marble_review_submission_id() {
  local MARBLE_ASC_APP_ID="$1" MARBLE_PLATFORM="$2" version_id="$3"
  local submissions_json submission_count submission_json submission_id items_json
  # Reuse only an unsubmitted draft containing this exact version and no
  # other items. A transport/create failure must never select an arbitrary
  # submission and submit unrelated work.
  submissions_json="$(asc review submissions-list --app "$MARBLE_ASC_APP_ID" --platform "$MARBLE_PLATFORM" --state READY_FOR_REVIEW --paginate --output json)" || return 1
  submission_count="$(printf '%s' "$submissions_json" | jq -er '.data | length')" || return 1
  if [[ "$submission_count" == 0 ]]; then
    submission_json="$(asc review submissions-create --app "$MARBLE_ASC_APP_ID" --platform "$MARBLE_PLATFORM" --output json)" || return 1
    submission_id="$(printf '%s' "$submission_json" | jq -er '.data | select(.attributes.state == "READY_FOR_REVIEW") | .id')" || return 1
    asc review items-add --submission "$submission_id" --item-type appStoreVersions --item-id "$version_id" >&2 || return 1
  elif [[ "$submission_count" == 1 ]]; then
    submission_id="$(printf '%s' "$submissions_json" | jq -er '.data[0] | select(.attributes.state == "READY_FOR_REVIEW") | .id')" || return 1
  else
    echo "error: multiple editable review submissions; resolve exact membership before retrying" >&2
    return 1
  fi
  items_json="$(asc review items-list --submission "$submission_id" --include appStoreVersion --paginate --output json)" || return 1
  printf '%s' "$items_json" | jq -e --arg version "$version_id" \
    '.data | length == 1 and .[0].relationships.appStoreVersion.data.id == $version' >/dev/null || {
    echo "error: review draft must contain only the exact verified App Store version; no submission sent" >&2
    return 1
  }
  printf '%s\n' "$submission_id"
}
