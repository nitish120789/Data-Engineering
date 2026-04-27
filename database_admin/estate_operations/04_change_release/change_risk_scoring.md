# Change Risk Scoring

**For comprehensive change management procedures (classification, validation, approval, rollback), see**:

[Change Management & Release Runbook](../../sre/runbooks/change-management-and-release.md)

That runbook covers:

- Three-tier risk classification (Tier-1 high-risk, Tier-2 medium, Tier-3 low)
- Pre-change validation and testing procedures
- Engine-specific non-blocking DDL approaches
- Phased execution with decision points and duration estimates
- Post-change verification and SLO attestation
- Rollback triggers and procedures
- Communication cadence by severity

## Quick Risk Scoring Guidance

Score each change on these dimensions:

- **Blast radius**: How many databases/workloads affected? (1 table vs. cross-shard?)
- **Data correctness risk**: Can data be corrupted by incorrect execution?
- **Rollback complexity**: How hard is it to undo? (Reversible vs. data-altering)
- **Runtime load impact**: Will change cause blocking/latency during execution?
- **Dependency coupling**: How many dependent systems affected?

**Use scoring to determine**:

- Approval depth (DBRE alone vs. DBRE + service owner + platform lead)
- Testing requirement (lab-only vs. staged vs. full production drill)
- Window type (flexible vs. scheduled maintenance window)
- Validation steps (spot-check vs. comprehensive verification)

See the full [Change Management & Release Runbook](../../sre/runbooks/change-management-and-release.md) for detailed risk matrices and engine-specific DDL strategies.
