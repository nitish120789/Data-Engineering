#!/usr/bin/env bash
# Cutover checklist runner for Oracle to Aurora PostgreSQL
# Author: Nitish Anand Srivastava

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  export DMS_TASK_ARN="arn:aws:dms:...:task:..."
  export DMS_LAG_CHECK_COMMAND="./ops/check_dms_lag_zero.sh"
  export SOURCE_FREEZE_COMMAND="./ops/freeze_oracle_writes.sh"
  export RECON_SCRIPT_PATH="./ops/run_final_reconciliation.sh"
  export SEQUENCE_RESEED_COMMAND="./ops/run_sequence_reseed.sh"   # optional
  export ROLLBACK_COMMAND="./ops/rollback_to_oracle.sh"           # optional
  export MAX_WAIT_SECONDS=1800
  export POLL_INTERVAL_SECONDS=15
  bash scripts/cutover_checklist.sh
EOF
}

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    fail "Missing required env var: ${name}"
  fi
}

run_cmd() {
  local cmd="$1"
  log "Executing: ${cmd}"
  # shellcheck disable=SC2086
  ${cmd}
}

require_cmd() {
  local name="$1"
  command -v "${name}" >/dev/null 2>&1 || fail "Required command not found: ${name}"
}

require_env DMS_TASK_ARN
require_env DMS_LAG_CHECK_COMMAND
require_env SOURCE_FREEZE_COMMAND
require_env RECON_SCRIPT_PATH

MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-1800}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-15}"
ROLLBACK_COMMAND="${ROLLBACK_COMMAND:-}"
SEQUENCE_RESEED_COMMAND="${SEQUENCE_RESEED_COMMAND:-}"

require_cmd bash
require_cmd date

case "${MAX_WAIT_SECONDS}" in
  ''|*[!0-9]*) usage; fail "MAX_WAIT_SECONDS must be an integer" ;;
esac

case "${POLL_INTERVAL_SECONDS}" in
  ''|*[!0-9]*) usage; fail "POLL_INTERVAL_SECONDS must be an integer" ;;
esac

log "Starting cutover checklist"
run_cmd "${SOURCE_FREEZE_COMMAND}"

elapsed=0
while [ "${elapsed}" -lt "${MAX_WAIT_SECONDS}" ]; do
  log "Checking DMS lag for ${DMS_TASK_ARN}; elapsed=${elapsed}s"
  if run_cmd "${DMS_LAG_CHECK_COMMAND}"; then
    log "DMS lag check passed"
    break
  fi

  sleep "${POLL_INTERVAL_SECONDS}"
  elapsed=$((elapsed + POLL_INTERVAL_SECONDS))
done

if [ "${elapsed}" -ge "${MAX_WAIT_SECONDS}" ]; then
  log "DMS did not drain within timeout"
  if [ -n "${ROLLBACK_COMMAND}" ]; then
    run_cmd "${ROLLBACK_COMMAND}"
  fi
  fail "Cutover aborted due to DMS lag timeout"
fi

run_cmd "${RECON_SCRIPT_PATH}"
if [ -n "${SEQUENCE_RESEED_COMMAND}" ]; then
  run_cmd "${SEQUENCE_RESEED_COMMAND}"
else
  log "SEQUENCE_RESEED_COMMAND not set; run scripts/sequence_reseed.sql before enabling writes"
fi
log "Manual go/no-go checkpoint required"
