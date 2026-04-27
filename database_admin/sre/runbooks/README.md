# SRE Runbooks Index

This directory contains operational runbooks for managing production databases. Each runbook follows a standardized format (Summary, Impact, Preconditions, Procedure, Verification, Rollback, Communication, Evidence) and includes practical commands and decision trees.

## Core Incident Response Runbooks

### Critical Path (Sev-1 Incidents)

| Runbook | Trigger | MTTR Target | Key Sections |
|---|---|---|---|
| [Incident Response - PostgreSQL](incident_response.md) | p95 latency spike, error rate spike, availability loss | <10 min stabilize | Triage SQL, blocking chains, failover decision |
| [Lock/Deadlock Triage & Resolution](lock-deadlock-triage-and-resolution.md) | Lock timeouts, deadlock errors, blocking sessions | <5 min resolve | Blocker analysis, termination decision, deadlock handling |
| [Failover Procedure](failover_procedure.md) | Primary unavailable, unsafe to write | <15 min complete | Replica promotion, traffic cutover, post-failover validation |
| [Disaster Recovery](disaster_recovery.md) | Major failure (site/region/corruption) | <60 min Tier-1 recovery | Scope prioritization, phased restore, drill program |

### Operational Procedures

| Runbook | Owner | Frequency | Key Sections |
|---|---|---|---|
| [Change Management & Release](change-management-and-release.md) | DBRE + App Owner | Per change | Risk classification, pre-change validation, rollback plan |
| [Backup Verification & Restore Drill](backup-verification-and-restore-drill.md) | DBRE + Storage Team | Monthly (Tier-1) | Backup integrity check, point-in-time restore, RTO/RPO validation |
| [Symptom-Driven Troubleshooting](symptom-driven-troubleshooting-decision-tree.md) | All DBAs | Per incident | Decision tree by symptom, quick diagnostics, escalation criteria |

## Platform-Specific Extensions

**Usage pattern**: Use core runbooks above; supplement with engine-specific guidance in platform folders:

- PostgreSQL: `database_admin/postgres/advanced/`
- SQL Server: `database_admin/sqlserver/ha_dr/`
- MySQL: `database_admin/mysql/replication/`
- Oracle: `database_admin/oracle/backup/`

Each platform folder contains engine-specific DDL, configuration, and recovery procedures.

## Cross-Cutting Runbooks

These apply across all platforms:

- [Alerting & Monitoring Configuration](../standards/alerting-and-monitoring-configuration.md)
- [Index Lifecycle Management](../indexing/index-lifecycle-management.md)
- [Security & Compliance Operating Standard](../standards/security-and-compliance-operating-standard.md)
- [Capacity & FinOps Operating Standard](../standards/capacity-and-finops-operating-standard.md)

## Runbook Use Flowchart

```
Incident Detected
    ↓
Is it an SLO breach or Sev-1?
    ├─ YES → Incident Response (By Engine)
    │        ├─ Blocking detected? → Lock/Deadlock Runbook
    │        ├─ Primary down? → Failover Runbook
    │        └─ Multi-system failure? → Disaster Recovery
    └─ NO → Symptom-Driven Decision Tree
             ├─ Slow queries? → Performance troubleshooting
             ├─ Connection error? → Connection pool investigation
             ├─ Replication lag? → HA monitoring
             └─ Data consistency? → Integrity checks

Before any change:
    → Change Management & Release Runbook (risk assessment, testing, validation)

Monthly operations:
    → Backup Verification & Restore Drill (prove RTO/RPO)
    → Alerting tuning (false alarm analysis)
```

Diagram description: High-level flowchart routing operators to the correct runbook based on incident type (SLO breach, symptom, or operational procedure).

## Runbook Standards

### Required Sections

Every runbook must include:

1. **Summary**: Purpose, scope, owner, escalation path
2. **Impact & Context**: SLO/RTO/RPO targets, reliability targets
3. **Preconditions**: Access, approvals, safety gates
4. **Preparation Checklist**: Steps before procedure
5. **Procedure**: Phased execution with decision points
6. **Verification**: Success criteria and validation checks
7. **Rollback**: How to undo if something goes wrong
8. **Communication**: Who updates, what, when
9. **Evidence**: What to log for audit trail

See template: [runbook_template.md](../templates/runbook_template.md)

### Quality Expectations

- **Actionable**: include concrete commands, not just descriptions
- **Time-boxed**: each section includes time estimate
- **Decision-driven**: branch on conditions (if X, then Y)
- **Tested**: all procedures exercised in drills at least quarterly
- **Maintained**: reviewed/updated after each use; stale runbooks flagged

## Common Patterns

### Session Termination Safety

Before terminating a database session:

1. Capture session query text and start time
2. Confirm with incident commander
3. Log decision (why terminating)
4. Execute termination
5. Monitor for cascading issues 30 seconds post-termination
6. Have escalation plan if termination causes new issues

### Post-Incident Review (PIR) Template

After each Sev-1 incident:

- What was the root cause?
- How quickly did we detect it? (detection time)
- How quickly did we resolve? (MTTR)
- What runbook gaps did we identify?
- What should we automate next?
- Any process improvements?

### Rollback Decision Tree

Can we rollback? (For each procedure)

```
Rollback needed?
  ├─ YES, and reversible → execute rollback
  ├─ YES, but not reversible → escalate to SRE/CTO
  └─ NO → continue monitoring
```

## Escalation Matrix

| Condition | Action | Escalation |
|---|---|---|
| Procedure not in runbook | pause; create ticket; escalate | SRE Incident Commander |
| Rollback fails | escalate immediately | SRE Incident Commander + CTO |
| Sev-1 unresolved > 15 min | escalate | On-Call Director |
| Data loss suspected | treat as Sev-1; preserve evidence; escalate | SRE Incident Commander + Legal |
| Unknown root cause > 10 min | escalate | Senior DBRE + SRE Lead |

## Accessing Runbooks During Incidents

- **Preferred**: runbook link in alert annotation → instant access from monitoring system
- **Fallback**: bookmark this index in browser; search by symptom
- **Backup**: git clone repo locally during onboarding; search offline if needed

## Contributing to Runbooks

To add or update a runbook:

1. Use the standard template: `database_admin/templates/runbook_template.md`
2. Include concrete commands (not just theory)
3. Add time estimates for each section
4. Include a rollback section
5. Test procedure in lab at least once before committing
6. Link to this index from your new runbook
7. Schedule quarterly review date

## Recent Additions

- [Change Management & Release](change-management-and-release.md) - New (handles Tier-1/2/3 risk classification)
- [Lock/Deadlock Triage](lock-deadlock-triage-and-resolution.md) - New (engine-agnostic blocking resolution)
- [Backup Verification Drill](backup-verification-and-restore-drill.md) - New (proves RTO/RPO)
- [Symptom Decision Tree](symptom-driven-troubleshooting-decision-tree.md) - New (triage flowchart)

## Planned Runbooks (Backlog)

- [ ] Connection Pool Tuning and Exhaustion Recovery
- [ ] Replication Lag Diagnosis & Resolution
- [ ] Query Plan Regression Deep Dive
- [ ] Autovacuum Tuning and Bloat Management (PostgreSQL)
- [ ] Statistics Refresh and Plan Re-optimization (SQL Server)
