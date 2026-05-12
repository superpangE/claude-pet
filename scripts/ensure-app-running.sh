#!/usr/bin/env bash
# Spawn the Electron pet app if not already running. Idempotent.
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$DIR/.." && pwd)}"
APP_DIR="$PLUGIN_ROOT/pet-app"
DATA_DIR="${CLAUDE_PET_DATA_DIR:-$HOME/.claude/plugins/claude-pet/data}"
PID_FILE="$DATA_DIR/app.pid"
LOG_FILE="$DATA_DIR/app.log"

mkdir -p "$DATA_DIR"

# Returns 0 (and prints PID) if a pet-app electron wrapper is already running.
# Identifies the wrapper by command shape: argv[0]=node, argv[1] is the local
# electron binary, argv[2] points at our pet-app dir. Field-level matching (not
# whole-line substring) avoids false positives from shells whose command line
# happens to mention these paths. Tolerates double-slash from trailing-slash
# concatenation (e.g., $PLUGIN_ROOT/pet-app vs $PLUGIN_ROOT//pet-app).
find_running_pet() {
  ps -axo pid=,command= 2>/dev/null \
    | awk '
        $2 == "node" \
          && $3 ~ /\/node_modules\/\.bin\/electron$/ \
          && $4 ~ /\/pet-app\/?$/ {
          print $1; found=1; exit
        }
        END { exit (found?0:1) }
      '
}

# Validate the PID file points at our wrapper (not a stale entry whose PID
# the OS recycled for an unrelated process).
pid_is_our_pet() {
  local pid="$1"
  [[ -z "$pid" ]] && return 1
  kill -0 "$pid" 2>/dev/null || return 1
  local cmd
  cmd="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  [[ "$cmd" == *"/pet-app"* && "$cmd" == *"node_modules/.bin/electron"* ]]
}

# Already running per PID file?
if [[ -f "$PID_FILE" ]]; then
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if pid_is_our_pet "$pid"; then
    exit 0
  fi
fi

# PID file missing/stale, but a previous run might still be alive (e.g., user
# spawned manually, prior crash before PID write). Adopt it instead of forking
# a duplicate.
existing="$(find_running_pet || true)"
if [[ -n "$existing" ]]; then
  echo "$existing" >"$PID_FILE"
  echo "[claude-pet] adopted existing pet pid=$existing" >>"$LOG_FILE"
  exit 0
fi

# Resolve electron binary: prefer local install, fall back to PATH.
ELECTRON_BIN="$APP_DIR/node_modules/.bin/electron"

# Lazy install on first run. A fresh clone (or fresh plugin marketplace fetch)
# arrives without pet-app/node_modules, since the dependency tree is ~100MB and
# we don't ship it. Run npm install synchronously here so the user doesn't have
# to know about a separate setup step. First call blocks for 1-2 minutes; later
# calls are no-ops because the binary now exists.
if [[ ! -x "$ELECTRON_BIN" && -f "$APP_DIR/package.json" ]]; then
  if command -v npm >/dev/null 2>&1; then
    echo "[claude-pet] first-time setup: installing electron deps (1-2 min)..." >>"$LOG_FILE"
    (cd "$APP_DIR" && npm install --no-audit --no-fund) >>"$LOG_FILE" 2>&1 || true
  else
    echo "[claude-pet] npm not found. Install Node.js 20+ then retry." >>"$LOG_FILE"
  fi
fi

if [[ ! -x "$ELECTRON_BIN" ]]; then
  ELECTRON_BIN="$(command -v electron || true)"
fi

if [[ -z "$ELECTRON_BIN" || ! -x "$ELECTRON_BIN" ]]; then
  echo "[claude-pet] electron not found. Run: cd \"$APP_DIR\" && npm install" >>"$LOG_FILE"
  exit 0
fi

# Spawn detached so the hook returns immediately.
nohup "$ELECTRON_BIN" "$APP_DIR" >>"$LOG_FILE" 2>&1 &
echo $! >"$PID_FILE"
disown 2>/dev/null || true
exit 0
