#!/usr/bin/env bash
# Stop hook: end-of-turn or mid-turn continuation.
# stop_hook_active=false → real end-of-turn → idle immediately.
# stop_hook_active=true  → mid-turn (subagent finish, internal continuation)
#                          → "stopping" (tentative idle, grace-windowed by the
#                          aggregator; cancelled by any UserPromptSubmit /
#                          PreToolUse / PostToolUse landing within the grace).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$DIR/_lib.sh"
PAYLOAD="$(cat || true)"

ACTIVE="$(printf '%s' "$PAYLOAD" | /usr/bin/python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print("1" if d.get("stop_hook_active") else "0")
except Exception:
    print("0")' 2>/dev/null || echo "0")"

if [[ "$ACTIVE" == "1" ]]; then
  write_session_state "stopping" "$PAYLOAD"
else
  write_session_state "idle" "$PAYLOAD"
fi
ensure_app_running
exit 0
