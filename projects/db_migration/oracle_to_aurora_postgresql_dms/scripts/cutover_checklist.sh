#!/usr/bin/env bash
# Cutover checklist runner for Oracle to Aurora PostgreSQL
# Author: Nitish Anand Srivastava

set -euo pipefail

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

require_env DMS_TASK_ARN
require_env DMS_LAG_CHECK_COMMAND
require_env SOURCE_FREEZE_COMMAND
require_env RECON_SCRIPT_PATH

MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-1800}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-15}"
ROLLBACK_COMMAND="${ROLLBACK_COMMAND:-}"

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
log "Run sequence reseed before enabling writes"
log "Manual go/no-go checkpoint required"
