# Alert Configuration and Operationalization Guide

## Overview

The SLI/SLO catalog defines targets; this guide operationalizes them into real alerts that trigger incident response. Alerts should be **predictive** (catch issues before SLO breach) and **actionable** (oncall can take immediate action).

## Alert Design Principles

### 1. Alert Hierarchy

- **Critical (Sev-1)**: SLO will breach in <5 minutes without intervention; page oncall immediately
- **Warning (Sev-2)**: SLO trending toward breach; likely incident within 15 minutes; page after confirmation
- **Info**: Operational metric worth tracking but not SLO-affecting; log only

### 2. Signal Quality

Each alert should have high signal-to-noise ratio:

- **High fidelity**: alert fires only when action required (not noisy false alarms)
- **Sufficient lead time**: alert fires before SLO breach, not after
- **Actionable**: the oncall engineer can immediately identify next step from alert name and context

### 3. Multi-Signal Correlation

Avoid single-metric alerts. Use composite logic:

Bad: "Alert when CPU > 80%"
- Fires on every CPU spike, even short-lived
- Doesn't correlate with actual SLO impact

Better: "Alert when CPU > 80% AND query latency p95 > 150ms for 2+ minutes"
- Fires only when CPU spike actually affects users
- Less noisy; actionable

## Alert Configuration by Signal Type

### 1. Latency Alerts (p95, p99)

**Goal**: detect when query response time exceeds SLO target.

```yaml
# Prometheus/Grafana example
alert: DatabaseLatencyBreach
  expr: histogram_quantile(0.95, rate(query_duration_ms[5m])) > 100
  for: 2m
  annotations:
    summary: "Database p95 latency {{ $value }}ms > target 100ms"
    runbook: "database_admin/sre/runbooks/incident_response.md"
    
alert: DatabaseLatencyWarning
  expr: histogram_quantile(0.95, rate(query_duration_ms[5m])) > 75
  for: 1m
  annotations:
    summary: "Database p95 latency {{ $value }}ms trending toward breach"
```

**Tuning**:

- **Evaluation window**: use 5-minute average to smooth out spikes
- **Duration**: require condition true for 2 min (Sev-1) or 1 min (Sev-2) before alert
- **Threshold**: set warning at 70-80% of SLO target; critical at 95%+

### 2. Throughput Alerts (TPS/QPS)

**Goal**: detect when query volume drops (indicating widespread failures) or spikes (load shock).

```yaml
alert: DatabaseThroughputDrop
  expr: rate(queries_total[5m]) < 1000  # Expected: 5000 QPS nominal
  for: 1m
  annotations:
    summary: "Database QPS dropped to {{ $value }} (expected >1000)"
    
alert: DatabaseThroughputSpike
  expr: rate(queries_total[5m]) > 20000  # 4x normal; likely attack or workload spike
  for: 30s
  annotations:
    summary: "Database QPS spiked to {{ $value }}"
```

**Tuning**:

- **Baseline**: establish normal range (e.g., 4000-6000 QPS); alert outside this
- **Spike threshold**: set at 2-4x normal baseline
- **Duration**: throughput spikes should trigger faster (30s) than latency (2m)

### 3. Error Rate Alerts

**Goal**: detect when error rate exceeds SLO budget burn rate.

```yaml
alert: ErrorRateBreach
  expr: rate(query_errors_total[5m]) / rate(queries_total[5m]) > 0.001  # >0.1%
  for: 2m
  annotations:
    summary: "Database error rate {{ $value | humanizePercentage }}"
    
alert: ErrorRateWarning
  expr: rate(query_errors_total[5m]) / rate(queries_total[5m]) > 0.0005  # >0.05%
  for: 1m
  annotations:
    summary: "Database error rate trending high"
```

### 4. Saturation Alerts (CPU, IOPS, Connections)

**Goal**: detect resource exhaustion before query queuing increases.

```yaml
alert: DatabaseCPUSaturation
  expr: avg(cpu_usage_percent) > 85
  for: 2m
  annotations:
    summary: "Database CPU {{ $value }}% for 2 minutes"
    
alert: DatabaseConnectionExhaustion
  expr: db_active_connections / db_max_connections > 0.9
  for: 1m
  annotations:
    summary: "Database connections {{ $value | humanizePercentage }} of max"
    
alert: DatabaseIOPSSaturation
  expr: avg(disk_read_write_iops / disk_iops_max) > 0.8
  for: 2m
  annotations:
    summary: "Database IOPS at {{ $value | humanizePercentage }} capacity"
```

**Tuning**:

- **CPU**: alert at 80-85% (leaves headroom for spike)
- **Connections**: alert at 85-90% of max
- **IOPS**: alert at 75-80% of provisioned capacity

### 5. Replication Lag Alerts (HA Environment)

**Goal**: detect replication backlog; ensure failover-ready state.

```yaml
alert: ReplicationLagHigh
  expr: replication_lag_seconds > 10  # Policy: must be <5s for failover readiness
  for: 2m
  annotations:
    summary: "Database replication lag {{ $value }}s (policy: <5s)"
    
alert: ReplicationLagCritical
  expr: replication_lag_seconds > 60
  for: 30s
  annotations:
    summary: "Database replication lag {{ $value }}s - failover may lose data"
```

### 6. Lock and Blocking Alerts

**Goal**: detect lock contention affecting SLO.

```yaml
alert: LongBlockingChain
  expr: max(blocked_sessions) > 10
  for: 1m
  annotations:
    summary: "{{ $value }} sessions blocked for >30s"
    runbook: "database_admin/sre/runbooks/lock-deadlock-triage-and-resolution.md"
    
alert: DeadlockRateHigh
  expr: rate(deadlocks_total[5m]) > 1  # More than 1 per 5 minutes
  for: 30s
  annotations:
    summary: "Deadlock rate {{ $value }}/min"
```

### 7. Backup and Recovery Alerts

**Goal**: ensure backup infrastructure is functional.

```yaml
alert: BackupMissing
  expr: time() - last_successful_backup_timestamp > 86400 + 3600  # >25 hours
  for: 10m
  annotations:
    summary: "No successful backup in past 25 hours"
    
alert: BackupSizeDrop
  expr: latest_backup_size_gb < avg_backup_size_gb * 0.5  # <50% of normal
  for: 5m
  annotations:
    summary: "Backup size {{ $value }}GB significantly below normal"
    
alert: RestoreDrillFailed
  expr: last_restore_drill_status != "success"
  for: 1m
  annotations:
    summary: "Last restore drill failed"
```

## Alert Context and Runbooks

Every critical alert should link to a runbook:

```yaml
alert: IncidentResponseNeeded
  annotations:
    summary: "{{ $value }} database issue"
    runbook: "https://internal.wiki/database_admin/sre/runbooks/incident_response.md"
    dashboard: "https://grafana/d/database_health"
    logs: "https://datadog/logs?query=database_errors"
```

Provide oncall with:

1. **Alert definition**: what the metric means
2. **Runbook link**: step-by-step resolution
3. **Dashboard link**: detailed metrics graph
4. **Log link**: recent error context

## Escalation and Notification

### Alert to Incident Classification

Map alert to severity and paging:

| Alert Type | Severity | Page Time | Escalation |
|---|---|---|---|
| SLO-affecting (latency/error/availability) | Sev-1 | Immediate | After 5 min unresolved |
| Resource saturation | Sev-2 | 5 minutes | If Sev-2 for >15 min or becomes Sev-1 |
| Operational (backup, replication lag) | Sev-3 | 30 minutes (business hours) | None; log ticket |

### Example Escalation Logic

```yaml
# Sev-1: immediate page
if alert.matches(['LatencyBreach', 'ErrorRateBreach', 'ConnectionExhaustion']):
  notify(oncall_dba, immediately=True)

# Sev-2: confirm then page
if alert.matches(['LatencyWarning', 'CPUSaturation']) and duration > 2m:
  notify(oncall_dba, delay=5m)

# Sev-3: ticket only
if alert.matches(['BackupMissing', 'ReplicationLagWarning']):
  create_ticket(priority='low')
```

## Common Pitfalls and Tuning

### Problem: Alert Fatigue

**Symptom**: oncall ignores page because alert fires for every workload spike

**Solution**:

- Add duration requirement (alert true for 2+ min before firing)
- Use multi-signal logic (latency + CPU, not either/or)
- Dynamically adjust thresholds by time-of-day (looser during maintenance windows)

### Problem: Alert Doesn't Fire When SLO Breached

**Symptom**: incident happens but alert was silent

**Solution**:

- Set warning threshold 10-20% below critical threshold
- Reduce evaluation window (e.g., 5m → 1m) for faster detection
- Add predictive alerts ("if trend continues, SLO will breach in X min")

### Problem: Alert Fires After SLO Already Breached

**Symptom**: alert fires after customers already impacted

**Solution**:

- Lower threshold to catch problem earlier
- Add leading indicator (e.g., CPU rising = latency will rise in 5 min)
- Increase frequency of metric collection (e.g., 1s instead of 60s)

## Testing Alerts

### Monthly Alert Drill

1. [ ] Fire each Sev-1 alert manually (disable auto-suppression)
2. [ ] Verify oncall receives page within 30 seconds
3. [ ] Verify runbook link is clickable and current
4. [ ] Verify dashboard context loads
5. [ ] Document any missing context or unclear runbook

### Quarterly Alert Tuning

Review past 3 months of alerts:

- How many alerts fired? (target: <10 per week for Sev-1)
- How many false alarms? (target: <20%)
- How many led to incident creation? (target: >70% of Sev-1)
- Average MTTR for each alert type? (target: <10 min)

## Alert Configuration Checklist

For each new alert:

- [ ] Business justification: why is this SLO-related?
- [ ] Threshold defined: what metric value triggers?
- [ ] Duration/confirmation: how long true before alert fires?
- [ ] Runbook linked: step-by-step resolution available?
- [ ] Dashboard provided: can oncall see context?
- [ ] Escalation policy: Sev-1/2/3 classification clear?
- [ ] Testing: alert tested and verified to fire?
- [ ] Documentation: alert name, intent, and thresholds documented?

## Practical Example: Complete Alert Definition

```yaml
alert: DatabaseLatencySLOBreach
  expr: |
    histogram_quantile(0.95, rate(mysql_query_duration_seconds_bucket[5m])) > 0.1
    and on() (
      rate(mysql_queries_total[5m]) > 1000  # Confirm actual traffic
    )
  for: 2m
  labels:
    severity: sev1
    service: database_platform
    runbook_url: "https://wiki/database_admin/sre/runbooks/incident_response.md"
  annotations:
    summary: "Database latency SLO breach: p95={{ humanizeDuration $value }}"
    description: "MySQL query p95 latency {{ humanizeDuration $value }} > SLO 100ms for 2+ minutes"
    dashboard: "https://grafana/d/mysql-health"
    logs_url: "https://datadog/logs?query=mysql_slow_queries"
    impact: "Users may experience slow page loads or timeouts"
    next_steps: "1. Check incident_response.md runbook; 2. Join bridge; 3. Investigate root cause"
```

## Alert Tuning Worksheet

| Alert Name | Threshold | Duration | False Alarms (30d) | True Positives (30d) | Tuning Action |
|---|---|---|---|---|---|
| LatencyBreach | >100ms | 2m | 2 | 8 | Lower threshold to 80ms (Sev-2) |
| CPUSaturation | >85% | 2m | 15 | 3 | Raise threshold to 90%; add connection saturation check |
| ErrorRate | >0.1% | 2m | 0 | 5 | Lower threshold to 0.05% for Sev-2 warning |
