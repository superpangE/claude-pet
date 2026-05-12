#!/usr/bin/env bash
# Send a control signal to the running pet Electron process.
# Usage: pet-control.sh show|hide
#
# SIGUSR1 -> hide window, SIGUSR2 -> show window. main.js wires these up.
# If the app isn't running, "show" spawns it; "hide" is a no-op.
set -u

CMD="${1:-}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$DIR/.." && pwd)}"
DATA_DIR="${CLAUDE_PET_DATA_DIR:-$HOME/.claude/plugins/claude-pet/data}"
PID_FILE="$DATA_DIR/app.pid"

case "$CMD" in
  show|hide) ;;
  *)
    echo "usage: pet-control.sh show|hide" >&2
    exit 2
    ;;
esac

pid=""
if [[ -f "$PID_FILE" ]]; then
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
fi

# Verify PID actually points at our pet wrapper, not a recycled unrelated PID.
if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
  cmd="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  if [[ "$cmd" != *"/pet-app"* || "$cmd" != *"node_modules/.bin/electron"* ]]; then
    pid=""  # PID is alive but not us — treat as not-running
  fi
fi

# Pet is running: signal it. Even if kill fails (rare: same-user perms),
# do NOT fall through to spawn — that would create an orphan second app.
#
# PID file holds the node `electron` launcher (the npm shim). It does NOT
# forward SIGUSR1/USR2 to the Electron binary it spawned, so signaling the
# wrapper is a no-op. Resolve its direct child (the Electron main process)
# and signal that instead.
if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
  target_pid="$(pgrep -P "$pid" 2>/dev/null | head -n1)"
  if [[ -z "$target_pid" ]]; then
    # Fall back to wrapper PID; better to try than to drop the request.
    target_pid="$pid"
  fi
  if [[ "$CMD" == "hide" ]]; then
    if kill -USR1 "$target_pid" 2>/dev/null; then
      echo "pet: hidden"
    else
      echo "pet: signal failed (pid $target_pid)" >&2
      exit 1
    fi
  else
    if kill -USR2 "$target_pid" 2>/dev/null; then
      echo "pet: shown"
    else
      echo "pet: signal failed (pid $target_pid)" >&2
      exit 1
    fi
  fi
  exit 0
fi

# Pet is not running.
if [[ "$CMD" == "show" ]]; then
  "$PLUGIN_ROOT/scripts/ensure-app-running.sh"
  echo "pet: starting"
  exit 0
fi
echo "pet: not running (nothing to hide)"
exit 0
