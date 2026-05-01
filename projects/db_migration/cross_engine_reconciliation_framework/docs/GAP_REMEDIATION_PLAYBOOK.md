# Gap Remediation Playbook

## Objective

Define deterministic actions when reconciliation gaps are detected.

## Gap Class to Fix Pattern

| Gap Class | Typical Root Cause | Primary Fix | Secondary Fix |
|---|---|---|---|
| CLASS-A Count mismatch | Missed batch, duplicate replay | Re-extract and replay affected key range | Delete-and-reload key range |
| CLASS-B Hash mismatch | Value transformation drift | Reconcile column-level diff and patch | Re-seed affected partitions |
| CLASS-C Update/delete mismatch | CDC lag/order issue | Replay from safe checkpoint window | Pause writes and perform final controlled catch-up |
| CLASS-D Constraint/object mismatch | Incomplete schema deployment | Reapply DDL and validate | Rebuild metadata with migration tooling |
| CLASS-E Encoding/precision drift | Inconsistent normalization | Canonicalize data and recalc hashes | Targeted conversion scripts |

## Standard Remediation Runbook

1. Create incident record with run id and affected tables
2. Freeze checkpoint movement for impacted scope
3. Localize mismatch (range/window/operation)
4. Choose remediation pattern from class table
5. Execute fix SQL or replay workflow
6. Re-run reconciliation on impacted scope
7. Run adjacent-range regression checks
8. Close incident only after green status

## Safety Guardrails

- Never run broad delete-and-reload without scoped WHERE clause.
- Always snapshot/backup target keys before destructive fix.
- Never advance CDC checkpoint manually without evidence.
- For Sev-1, require dual approval before applying invasive fixes.

## Verification Checklist After Fix

- Count parity restored
- Hash parity restored
- Update/delete parity restored
- Constraints valid and enabled
- No new mismatch in adjacent ranges
