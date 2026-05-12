#!/usr/bin/env bash
# Heartbeat hook: refreshes the session's updated_at while a tool runs so the
# Electron app keeps showing "working" even on long jobs (the only other
# trigger is UserPromptSubmit, which fires once per turn).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$DIR/_lib.sh"
PAYLOAD="$(cat || true)"
write_session_state "working" "$PAYLOAD"
ensure_app_running
exit 0
