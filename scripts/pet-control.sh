#!/usr/bin/env bash
# Control the running pet from the /pet slash command.
# Usage:
#   pet-control.sh show
#   pet-control.sh hide
#   pet-control.sh set <theme>
#   pet-control.sh list
#
# show/hide: SIGUSR1 = hide, SIGUSR2 = show — main.js handles these.
# set:       writes data/config.json; main.js's fs.watch picks it up live.
# list:      prints discoverable themes (one per line, current marked '*').
set -u

CMD="${1:-}"
ARG="${2:-}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$DIR/.." && pwd)}"
DATA_DIR="${CLAUDE_PET_DATA_DIR:-$HOME/.claude/plugins/claude-pet/data}"
PETS_DIR="$PLUGIN_ROOT/pet-app/assets/pets"
CONFIG_FILE="$DATA_DIR/config.json"

case "$CMD" in
  show|hide|set|list) ;;
  *)
    echo "usage: pet-control.sh show|hide | set <theme> | list" >&2
    exit 2
    ;;
esac

list_themes() {
  [[ -d "$PETS_DIR" ]] || return 0
  for d in "$PETS_DIR"/*/; do
    [[ -d "$d" ]] || continue
    local name
    name="$(basename "$d")"
    # Has at least one working/idle asset?
    for state in working idle; do
      for ext in svg gif webp apng png; do
        if [[ -f "$d/$state.$ext" ]]; then
          echo "$name"
          break 2
        fi
      done
    done
  done
}

current_theme() {
  if [[ -f "$CONFIG_FILE" ]] && command -v /usr/bin/python3 >/dev/null 2>&1; then
    /usr/bin/python3 -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("theme","cat"))
except Exception:
    print("cat")' "$CONFIG_FILE" 2>/dev/null
  else
    echo "cat"
  fi
}

case "$CMD" in
  list)
    cur="$(current_theme)"
    while IFS= read -r t; do
      if [[ "$t" == "$cur" ]]; then echo "* $t"; else echo "  $t"; fi
    done < <(list_themes | sort -u)
    exit 0
    ;;
  set)
    if [[ -z "$ARG" ]]; then
      echo "usage: pet-control.sh set <theme>" >&2
      exit 2
    fi
    if ! list_themes | grep -qx "$ARG"; then
      echo "pet: unknown theme '$ARG'. available:" >&2
      list_themes | sed 's/^/  /' >&2
      exit 1
    fi
    mkdir -p "$DATA_DIR"
    tmp="${CONFIG_FILE}.$$.tmp"
    printf '{"theme":"%s"}\n' "$ARG" >"$tmp"
    mv "$tmp" "$CONFIG_FILE"
    echo "pet: theme -> $ARG"
    # If app isn't running, spawn it so the change is visible immediately.
    "$PLUGIN_ROOT/scripts/ensure-app-running.sh" >/dev/null 2>&1 || true
    exit 0
    ;;
esac

# show / hide path below.
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
