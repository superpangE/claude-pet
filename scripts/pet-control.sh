#!/usr/bin/env bash
# Send a control signal to running pet Electron processes.
# Usage: pet-control.sh show|hide
#
# SIGUSR1 -> hide window, SIGUSR2 -> show window. main.js wires these up.
# Enumerates all pet wrappers via ps pattern match (not the PID file alone),
# so duplicate or leftover instances all get toggled. The PID file is
# advisory only and may drift (race on spawn, stale after crash, or shared
# between old/new plugin versions writing the same data dir).
set -u

CMD="${1:-}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$DIR/.." && pwd)}"

case "$CMD" in
  show|hide) ;;
  *)
    echo "usage: pet-control.sh show|hide" >&2
    exit 2
    ;;
esac

# All pet wrapper PIDs (node electron shim). Identified by command shape:
# argv[0]=node, argv[1] is the local electron binary, argv[2] is a pet-app
# dir. Field-level match (not whole-line substring) avoids false positives.
find_pet_pids() {
  ps -axo pid=,command= 2>/dev/null \
    | awk '
        $2 == "node" \
          && $3 ~ /\/node_modules\/\.bin\/electron$/ \
          && $4 ~ /\/pet-app\/?$/ {
          print $1
        }'
}

WRAPPERS=()
while IFS= read -r p; do
  [[ -n "$p" ]] && WRAPPERS+=("$p")
done < <(find_pet_pids)

if [[ ${#WRAPPERS[@]} -eq 0 ]]; then
  if [[ "$CMD" == "show" ]]; then
    "$PLUGIN_ROOT/scripts/ensure-app-running.sh"
    echo "pet: starting"
    exit 0
  fi
  echo "pet: not running (nothing to hide)"
  exit 0
fi

SIG=USR1
LABEL=hidden
if [[ "$CMD" == "show" ]]; then
  SIG=USR2
  LABEL=shown
fi

fail=0
for wrapper in "${WRAPPERS[@]}"; do
  # The node shim does NOT forward SIGUSR1/USR2 to the Electron binary it
  # spawned. Resolve its direct child (Electron main) and signal that.
  child="$(pgrep -P "$wrapper" 2>/dev/null | head -n1)"
  target="${child:-$wrapper}"
  if ! kill -"$SIG" "$target" 2>/dev/null; then
    fail=$((fail + 1))
  fi
done

if [[ $fail -eq ${#WRAPPERS[@]} ]]; then
  echo "pet: signal failed (${#WRAPPERS[@]} pid(s))" >&2
  exit 1
fi
echo "pet: $LABEL (${#WRAPPERS[@]} instance(s))"
exit 0
