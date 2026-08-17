#!/usr/bin/env bash
# Idempotent Cursor Cloud Agent install. Linux VMs cannot run xcodebuild;
# this only installs the App Store Connect CLI so agents can talk to ASC
# and drive the GitHub Actions Mac release jobs.
set -euo pipefail

log() { printf '[cursor-cloud-install] %s\n' "$*"; }

install_asc() {
  if command -v asc >/dev/null 2>&1; then
    log "asc already installed: $(asc --version 2>/dev/null || echo present)"
    return 0
  fi

  log "installing App Store Connect CLI"
  curl -fsSL https://asccli.sh/install | bash

  # Official installer typically drops the binary in ~/.local/bin or /usr/local/bin.
  export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
  if ! command -v asc >/dev/null 2>&1; then
    log "error: asc install finished but the binary is not on PATH"
    return 1
  fi
  log "asc installed: $(asc --version 2>/dev/null || echo present)"
}

ensure_jq() {
  if command -v jq >/dev/null 2>&1; then
    return 0
  fi
  if command -v apt-get >/dev/null 2>&1; then
    log "installing jq"
    sudo apt-get update -qq
    sudo apt-get install -y -qq jq
    return 0
  fi
  log "warning: jq is not installed and apt-get is unavailable"
}

# python3 is used by scripts/lib/marble_release.sh to read MARKETING_VERSION
# from the Xcode project on Linux (ruby is a Mac/CI default, not this image).
ensure_python() {
  if command -v python3 >/dev/null 2>&1; then
    return 0
  fi
  log "error: python3 is required"
  return 1
}

ensure_path_snippet() {
  local snippet='export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"'
  local bashrc="${HOME}/.bashrc"
  if [[ -f "$bashrc" ]] && grep -Fq '.local/bin' "$bashrc"; then
    return 0
  fi
  printf '\n# Marble cloud release CLI\n%s\n' "$snippet" >> "$bashrc"
}

ensure_asc_ci_defaults() {
  # Headless auth: never try the Linux keyring.
  mkdir -p "${HOME}/.asc"
  local env_file="${HOME}/.asc/env"
  if [[ ! -f "$env_file" ]]; then
    printf 'ASC_BYPASS_KEYCHAIN=true\n' > "$env_file"
  fi
}

main() {
  ensure_python
  ensure_jq
  install_asc
  ensure_path_snippet
  ensure_asc_ci_defaults
  log "done. Binary publish still runs on GitHub Actions macos-26; this VM is API + dispatch only."
}

main "$@"
