#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$DIR/_lib.sh"
PAYLOAD="$(cat || true)"
# Initialize this session as idle so the aggregator counts it as active.
write_session_state "idle" "$PAYLOAD"
ensure_app_running
exit 0
