#!/usr/bin/env bash
# Cutover orchestration skeleton for Oracle -> Azure PostgreSQL
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

require_cmd() {
  local name="$1"
  command -v "${name}" >/dev/null 2>&1 || fail "Required command not found: ${name}"
}

require_env SOURCE_FREEZE_COMMAND
require_env DMS_TASK_NAME
require_env RECON_SCRIPT_PATH
require_env DMS_LAG_CHECK_COMMAND

DMS_MAX_WAIT_SECONDS="${DMS_MAX_WAIT_SECONDS:-1800}"
DMS_POLL_INTERVAL_SECONDS="${DMS_POLL_INTERVAL_SECONDS:-15}"
ROLLBACK_COMMAND="${ROLLBACK_COMMAND:-}"

require_cmd date
require_cmd bash

log "Starting cutover orchestration"

log "Step 1: Enforcing source write freeze"
run_cmd "${SOURCE_FREEZE_COMMAND}"

log "Step 2: Waiting for DMS lag drain"
elapsed=0
while [ "${elapsed}" -lt "${DMS_MAX_WAIT_SECONDS}" ]; do
  log "Polling DMS task ${DMS_TASK_NAME}; elapsed=${elapsed}s"
  if run_cmd "${DMS_LAG_CHECK_COMMAND}"; then
    log "DMS lag check indicates drain criteria met"
    break
  fi

  sleep "${DMS_POLL_INTERVAL_SECONDS}"
  elapsed=$((elapsed + DMS_POLL_INTERVAL_SECONDS))
done

if [ "${elapsed}" -ge "${DMS_MAX_WAIT_SECONDS}" ]; then
  log "DMS lag did not drain within ${DMS_MAX_WAIT_SECONDS}s"
  if [ -n "${ROLLBACK_COMMAND}" ]; then
    log "Running rollback command due to DMS timeout"
    run_cmd "${ROLLBACK_COMMAND}"
  fi
  fail "Cutover aborted due to DMS drain timeout"
fi

log "Step 3: Running final reconciliation suite"
run_cmd "${RECON_SCRIPT_PATH}"

log "Step 4: Manual go/no-go checkpoint required"
log "If GO, switch application endpoint and rotate credentials"
log "If NO-GO, execute rollback script and unfreeze source writes"

log "Cutover orchestration skeleton completed"
