# Cutover Validation and Reconciliation
## Oracle to Azure PostgreSQL Flexible Server

## 1. Validation Philosophy

Technical parity alone is insufficient. Cutover approval requires both:
- Technical consistency: row counts, hashes, PK/FK integrity, sequence correctness
- Business consistency: KPI outputs and workflow outcomes within signed tolerances

## 2. Reconciliation Layers

Layer 1: Structural
- Table/object presence and schema consistency
- Constraint state and index availability

Layer 2: Quantitative
- Table-level row counts
- Partition/window counts for large fact tables

Layer 3: Deterministic content checks
- Hash/checksum validation on key entity slices
- Nullability and domain checks on critical columns

Layer 4: Business KPI parity
- Revenue, settlement, inventory, risk, and SLA metrics
- Signed tolerance matrix by business owner

Layer 5: Operational correctness
- CDC lag is zero or within approved threshold at freeze
- No unresolved replication errors in DMS logs

## 3. Cutover Gate Checklist

Pre-freeze gate:
- DMS lag stable and no sustained error spikes
- All high-severity conversion defects closed
- Monitoring and rollback channels green

Freeze gate:
- Source write block enabled and confirmed
- DMS processing caught up to checkpoint
- Final replay cycle completed

Go-live gate:
- Reconciliation reports pass critical thresholds
- Smoke tests pass for critical app journeys
- CAB go decision documented

Post-switch gate:
- KPI parity checks pass
- No critical incident in first 30/60/120 minutes
- Sequence values validated for write paths

## 4. Mismatch Classification

- Class A (Critical): Financial/security/compliance impact
- Class B (High): Core user journey broken or severe data drift
- Class C (Medium): Non-critical reporting discrepancy
- Class D (Low): Cosmetic/metadata mismatch with no functional impact

Disposition policy:
- Class A/B block go-live unless explicitly risk-accepted by governance.
- Class C may proceed with remediation plan and owner approval.
- Class D tracked in hypercare backlog.

## 5. Typical Root Causes During Cutover

- Late source writes after freeze due to bypassed app channels
- Sequence misalignment on hot tables
- Time zone conversion inconsistencies in reporting logic
- DMS apply retries masking transient conflicts
- Partial validation coverage missing business edge cases

## 6. Recommended Evidence Artifacts

- Final reconciliation report (table + business layer)
- DMS final task status export
- SCN and checkpoint records
- App smoke test transcript
- CAB go/no-go decision log

## Author

Author: Nitish Anand Srivastava
