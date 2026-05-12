#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$DIR/_lib.sh"
PAYLOAD="$(cat || true)"
# Initialize this session as idle so the aggregator counts it as active.
write_session_state "idle" "$PAYLOAD"

# Pre-flight: verify Node.js 20+ and npm. The pet runs on Electron, which
# needs both. Without them ensure-app-running silently fails and the user
# sees no pet and no reason. SessionStart stdout is injected into Claude's
# session context, so a clear warning here surfaces in the user's session.
check_prereqs() {
  local missing=()

  if ! command -v node >/dev/null 2>&1; then
    missing+=("Node.js 20+ (install from https://nodejs.org/)")
  else
    local major
    major="$(node --version 2>/dev/null | sed -E 's/^v?([0-9]+).*/\1/')"
    if [[ -z "$major" || "$major" -lt 20 ]]; then
      local cur
      cur="$(node --version 2>/dev/null || echo 'unknown')"
      missing+=("Node.js 20+ (found ${cur}; upgrade at https://nodejs.org/)")
    fi
  fi

  if ! command -v npm >/dev/null 2>&1; then
    missing+=("npm (bundled with Node.js)")
  fi

  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi

  echo "[claude-pet] Cannot start the floating cat — missing prerequisites:"
  for m in "${missing[@]}"; do
    echo "  - $m"
  done
  echo "After installing, start a new Claude Code session. Other plugin"
  echo "features (commands, hooks) keep working without the cat."
  log "prereq missing: ${missing[*]}"
  return 1
}

if check_prereqs; then
  ensure_app_running
fi
exit 0
