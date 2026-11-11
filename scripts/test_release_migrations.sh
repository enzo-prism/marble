#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Test current production plus retained 2.5 and 2.4 upgrade coverage.
if [[ -n "${MIGRATION_BASE_REF:-}" ]]; then
    exec "$ROOT_DIR/scripts/test_previous_release_migration.sh"
fi
for base in 080d83445ef5c91b64da0559b88177b0857a8dc9 80396c19481739184aaca00e5f175512b7a92ded 9e8346f6cad4683991a78fbaf223baaf01e9f068; do
    MIGRATION_BASE_REF="$base" "$ROOT_DIR/scripts/test_previous_release_migration.sh"
done
