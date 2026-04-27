# Database Standards

This folder contains cross-platform DBRE standards that apply across engines and environments.

## Standards Index

### Operational Standards

- [Security & Compliance Operating Standard](security-and-compliance-operating-standard.md)
  - Identity/access controls, data protection, audit logging, configuration hardening, patch management
- [Capacity & FinOps Operating Standard](capacity-and-finops-operating-standard.md)
  - Capacity forecasting, optimization playbook, cost governance, SLO-tied decisions
- [Alerting & Monitoring Configuration](alerting-and-monitoring-configuration.md)
  - Alert hierarchy, signal quality, configuration by metric type, escalation logic, tuning

### Reference Materials

- `version_compatibility_matrix.md`

## How to Use

1. Start with these standards before writing engine-specific procedures.
2. Reference these standards in runbooks and change plans.
3. Document only platform-specific deviations in platform folders (e.g., `database_admin/postgres/`).
4. Use the standards to drive operational policy (e.g., "Patch critical CVEs within 7 days per security-and-compliance-operating-standard.md").

## Example Usage Patterns

### For DBAs writing a new runbook:

- Use Security & Compliance standard to add security checkpoint sections
- Use Alerting & Monitoring standard to define SLO thresholds and alert targets
- Use Capacity & FinOps standard for resource planning or cost-aware decisions

### For infrastructure teams:

- Use Alerting & Monitoring to tune alert thresholds per engine/tier
- Use Capacity & FinOps to drive right-sizing decisions
- Use Security & Compliance for access control and audit policies

## Review Cadence

- **Quarterly minimum**: review each standard for relevance and update if needed
- **After major incident**: immediately update if root cause exposed standard gap
- **After platform upgrade**: review security and capacity standards
- **After regulatory change**: review compliance standard

## Governance

Each standard includes:

- Clear requirements (MUST, SHOULD, MAY language)
- Practical examples and commands
- Decision tables and escalation matrices
- Automation recommendations
- Evidence/audit trail guidance

Non-compliance should be documented as exceptions with risk acceptance from service owner + security lead (where applicable).
