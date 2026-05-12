#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$DIR/_lib.sh"
PAYLOAD="$(cat || true)"
write_session_state "idle" "$PAYLOAD"
mark_session_attention "$PAYLOAD"
ensure_app_running
exit 0
