#!/usr/bin/env bash
# Shared helpers for claude-pet hook scripts.
# Sourced by on-*.sh

set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DATA_DIR="${CLAUDE_PET_DATA_DIR:-$HOME/.claude/plugins/claude-pet/data}"
LOG_FILE="$DATA_DIR/hook.log"
SESSIONS_DIR="$DATA_DIR/sessions"

mkdir -p "$DATA_DIR" "$SESSIONS_DIR"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$LOG_FILE"
}

# Echo "session_id|cwd" extracted from a Claude Code hook payload (JSON).
parse_payload() {
  printf '%s' "$1" | /usr/bin/python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print((d.get("session_id","") or "")+"|"+(d.get("cwd","") or ""))
except Exception:
    print("|")' 2>/dev/null || printf '|'
}

# Sanitize a session id for filesystem use (alphanumerics, dash, underscore only).
sanitize_sid() {
  local sid="${1//[^a-zA-Z0-9_-]/}"
  printf '%s' "$sid"
}

# write_session_state <state-name> <payload-json>
# Atomically writes sessions/<sid>.json. The Electron app watches the directory
# and aggregates across all session files (priority: working > idle).
# Side effect: clears any pending attention flag, since user-driven activity
# (UserPromptSubmit / ToolUse / Stop) means the prior Notification was handled.
write_session_state() {
  local new_state="$1"
  local payload="$2"
  local parsed session_id cwd ts target tmp
  parsed="$(parse_payload "$payload")"
  session_id="$(sanitize_sid "${parsed%%|*}")"
  cwd="${parsed#*|}"
  if [[ -z "$session_id" ]]; then
    log "skip: missing session_id (state=${new_state})"
    return 0
  fi
  ts="$(date +%s)"
  target="$SESSIONS_DIR/$session_id.json"
  tmp="$(mktemp "${target}.XXXXXX")"
  cat >"$tmp" <<EOF
{
  "session_id": "${session_id}",
  "state": "${new_state}",
  "cwd": "${cwd}",
  "updated_at": ${ts}
}
EOF
  mv "$tmp" "$target"
  rm -f "$SESSIONS_DIR/$session_id.attention"
  log "session=${session_id} state=${new_state}"
}

# Mark the session as needing user attention (e.g., permission prompt).
# Stored as a sibling marker file so the main state write stays a single
# atomic op. Cleared by the next write_session_state call.
mark_session_attention() {
  local payload="$1"
  local parsed session_id
  parsed="$(parse_payload "$payload")"
  session_id="$(sanitize_sid "${parsed%%|*}")"
  if [[ -z "$session_id" ]]; then
    log "skip attention: missing session_id"
    return 0
  fi
  : >"$SESSIONS_DIR/$session_id.attention"
  log "session=${session_id} attention"
}

# Remove the per-session state file. Called from on-session-end.sh.
mark_session_ended() {
  local sid
  sid="$(sanitize_sid "$1")"
  [[ -z "$sid" ]] && return 0
  rm -f "$SESSIONS_DIR/$sid.json" "$SESSIONS_DIR/$sid.attention"
  log "session end: $sid"
}

ensure_app_running() {
  "$PLUGIN_ROOT/scripts/ensure-app-running.sh" >>"$LOG_FILE" 2>&1 &
  disown 2>/dev/null || true
}
