#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$DIR/_lib.sh"
PAYLOAD="$(cat || true)"
PARSED="$(parse_payload "$PAYLOAD")"
mark_session_ended "${PARSED%%|*}"
exit 0
