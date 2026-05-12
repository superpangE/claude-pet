#!/usr/bin/env bash
# Control the running pet from the /pet slash command.
# Usage:
#   pet-control.sh show
#   pet-control.sh hide
#   pet-control.sh list
#   pet-control.sh set                       # no args -> emit a PICK prompt
#   pet-control.sh set <name>                # both states -> <name>
#   pet-control.sh set idle <name>           # only idle
#   pet-control.sh set working <name>        # only working
#
# show/hide: SIGUSR1 / SIGUSR2 to the running pet (main.js handles).
# set:       writes data/config.json; main.js fs.watch picks it up live.
# list:      prints "* current" / "  other".
set -u

CMD="${1:-}"
ARG1="${2:-}"
ARG2="${3:-}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$DIR/.." && pwd)}"
DATA_DIR="${CLAUDE_PET_DATA_DIR:-$HOME/.claude/plugins/claude-pet/data}"
PETS_DIR="$PLUGIN_ROOT/pet-app/assets/pets"
CONFIG_FILE="$DATA_DIR/config.json"

case "$CMD" in
  show|hide|set|list) ;;
  *)
    echo "usage: pet-control.sh show|hide | list | set [idle|working] <theme>" >&2
    exit 2
    ;;
esac

list_themes() {
  [[ -d "$PETS_DIR" ]] || return 0
  for d in "$PETS_DIR"/*/; do
    [[ -d "$d" ]] || continue
    local name
    name="$(basename "$d")"
    for state in working idle; do
      for ext in svg gif webp apng png; do
        if [[ -f "$d/$state.$ext" ]]; then
          echo "$name"
          break 2
        fi
      done
    done
  done | sort -u
}

current_themes() {
  /usr/bin/python3 - "$CONFIG_FILE" <<'PY' 2>/dev/null || echo "cat cat"
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    t = d.get("theme", "cat")
    if isinstance(t, str):
        print(f"{t} {t}")
    elif isinstance(t, dict):
        print(f"{t.get('idle','cat')} {t.get('working','cat')}")
    else:
        print("cat cat")
except Exception:
    print("cat cat")
PY
}

write_themes() {
  local idle="$1"
  local working="$2"
  mkdir -p "$DATA_DIR"
  local tmp="${CONFIG_FILE}.$$.tmp"
  if [[ "$idle" == "$working" ]]; then
    printf '{"theme":"%s"}\n' "$idle" >"$tmp"
  else
    printf '{"theme":{"idle":"%s","working":"%s"}}\n' "$idle" "$working" >"$tmp"
  fi
  mv "$tmp" "$CONFIG_FILE"
}

case "$CMD" in
  list)
    read -r cur_idle cur_working < <(current_themes)
    echo "idle:    $cur_idle"
    echo "working: $cur_working"
    echo "available:"
    while IFS= read -r t; do
      mark=" "
      [[ "$t" == "$cur_idle" || "$t" == "$cur_working" ]] && mark="*"
      echo "  $mark $t"
    done < <(list_themes)
    exit 0
    ;;
  set)
    # No args → print a structured PICK block so the LLM in the loop can
    # turn it into an interactive radio (AskUserQuestion). Humans typing
    # the bare /pet set in a real shell also get a readable list.
    if [[ -z "$ARG1" ]]; then
      read -r cur_idle cur_working < <(current_themes)
      echo "PET_PICK"
      echo "current_idle=$cur_idle"
      echo "current_working=$cur_working"
      echo "available:"
      list_themes | sed 's/^/  /'
      echo
      echo "usage: /pet set <name>            (both states)"
      echo "       /pet set idle <name>"
      echo "       /pet set working <name>"
      exit 0
    fi

    read -r cur_idle cur_working < <(current_themes)
    target_state=""
    name=""
    case "$ARG1" in
      idle|working)
        target_state="$ARG1"
        name="$ARG2"
        if [[ -z "$name" ]]; then
          echo "usage: /pet set $ARG1 <theme>" >&2
          exit 2
        fi
        ;;
      *)
        # `set <name>` → apply to both
        name="$ARG1"
        ;;
    esac

    if ! list_themes | grep -qx "$name"; then
      echo "pet: unknown theme '$name'. available:" >&2
      list_themes | sed 's/^/  /' >&2
      exit 1
    fi

    case "$target_state" in
      idle)    write_themes "$name" "$cur_working"; echo "pet: idle -> $name" ;;
      working) write_themes "$cur_idle" "$name";    echo "pet: working -> $name" ;;
      "")      write_themes "$name" "$name";        echo "pet: theme -> $name" ;;
    esac

    "$PLUGIN_ROOT/scripts/ensure-app-running.sh" >/dev/null 2>&1 || true
    exit 0
    ;;
esac

# show / hide path
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
