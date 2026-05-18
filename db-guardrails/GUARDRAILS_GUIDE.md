# Database Guardrails: AI-SQL Protection System

## Overview

A comprehensive framework to protect production databases from AI-generated SQL risks. Provides multi-layer defense including static analysis, runtime guards, mutation tracking, and CI/CD integration.

## What It Protects Against

1. **Mutation Risks**: DELETE/UPDATE without WHERE clauses
2. **SQL Injection**: Dynamic SQL with string concatenation
3. **Query Complexity**: Long-running queries causing locks
4. **Performance Issues**: Full table scans, missing indexes
5. **Data Loss**: TRUNCATE without safeguards
6. **Anti-Patterns**: Correlated subqueries, type conversions in WHERE
7. **Deprecated Functions**: Old T-SQL patterns

## Components

### SQL Scripts (Database-Level)
- `01_detect_ai_antipatterns.sql` — Scans stored procedures for risky patterns
- `02_query_complexity_risk_scoring.sql` — Analyzes query plans and missing indexes
- `03_mutation_safeguard_monitor.sql` — Tracks all INSERT/UPDATE/DELETE operations
- `04_transaction_lock_guard.sql` — Monitors blocking chains and long transactions

### Python Tools (Pre-Deployment)
- `sql_static_analyzer.py` — Static analysis before code reaches database
- `query_execution_guard.py` — Runtime query validation

### CI/CD Integrations
- `github_actions_workflow.yml` — Automated PR checks
- `pre-commit-guardrails.sh` — Git pre-commit hook
- `k8s_guardrails_cronjob.yaml` — Kubernetes periodic audits
- `awx_guardrails_playbook.yml` — Ansible/AWX orchestration

### Configuration
- `guardrails.yaml` — Centralized policy and sensitivity controls

---

## Quick Start

### 1. Database-Level Guardrails (SQL Server)

Run these scripts on your target database to enable monitoring:

```sql
-- Enable mutation audit table
SQLCMD -S your-server -d your-db -i scripts\03_mutation_safeguard_monitor.sql

-- Check for current violations
SQLCMD -S your-server -d your-db -i scripts\01_detect_ai_antipatterns.sql

-- Monitor active transactions
SQLCMD -S your-server -d your-db -i scripts\04_transaction_lock_guard.sql
```

### 2. Pre-Deployment Static Analysis

Before deploying any SQL code:

```bash
# Analyze single SQL file (strict mode blocks HIGH severity issues)
python scripts/sql_static_analyzer.py --file migrations/20260518_new_stored_proc.sql --strict

# Read from stdin
cat query.sql | python scripts/sql_static_analyzer.py --stdin --format json

# Strict enforcement (fails on HIGH severity)
python scripts/sql_static_analyzer.py --file query.sql --strict --format json
```

**Exit Codes:**
- 0 = Passed all checks
- 1 = Critical or (strict mode + HIGH severity) violations

### 3. Git Pre-Commit Hook

Prevent risky SQL from being committed:

```bash
# Install hook
cp db-guardrails/hooks/pre-commit-guardrails.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# Now commits with SQL violations automatically fail
git add migrations/risky_delete.sql
git commit -m "Add migration"
# ❌ Pre-commit check failed: 1 file(s) have critical issues
```

### 4. GitHub Actions (Automated PR Checks)

In your `.github/workflows/` directory:

```yaml
name: Database Guardrails

on: [pull_request]

jobs:
  guardrails:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v4
        with:
          python-version: '3.10'
      - run: python db-guardrails/scripts/sql_static_analyzer.py --file migration.sql --strict
```

Every PR with SQL files gets automatic analysis. CRITICAL violations block merge.

### 5. Kubernetes Monitoring (Continuous Audit)

```bash
# Create secrets
kubectl create secret generic db-guardrails-secrets \
  --from-literal=sqlserver-host=sql-prod.contoso.com \
  --from-literal=sqlserver-database=OrderDB \
  --from-literal=sqlserver-user=readonly_user \
  --from-literal=sqlserver-password=$(pass db/readonly) \
  -n database-ops

# Deploy CronJob
kubectl apply -f db-guardrails/ci-cd/k8s_guardrails_cronjob.yaml

# Runs daily at 2 AM UTC; sends alerts if violations exceed thresholds
```

### 6. Ansible/AWX Orchestration

```bash
# Deploy guardrails to managed database servers
ansible-playbook db-guardrails/ci-cd/awx_guardrails_playbook.yml \
  -i inventory/prod.ini \
  --tags "db-guardrails"

# Sets up:
# - Hourly mutation monitoring
# - Daily anti-pattern detection
# - Alert routing to Slack/Email
```

---

## Configuration

Edit `config/guardrails.yaml` to customize behavior:

### Enforcement Levels

```yaml
enforcement:
  level: 'moderate'  # strict, moderate, or permissive
```

- **strict**: Block CRITICAL + HIGH violations
- **moderate**: Block CRITICAL; alert on HIGH
- **permissive**: Log all violations; never block

### Execution Limits

```yaml
execution:
  max_execution_seconds: 30      # Kill queries exceeding this
  max_row_output: 1000000        # Warn if result set exceeds this
  statement_timeout_ms: 30000    # SQL Server timeout
```

### Risk Scoring

Customize what constitutes "risky":

```yaml
risk_scoring:
  delete_without_where: 100      # Critical
  update_without_where: 100      # Critical
  correlated_subquery_risk: 20   # Medium
  hardcoded_values: 10            # Low
```

### Whitelist Trusted Users/Queries

```yaml
whitelist:
  privileged_users:
    - 'sa'
    - 'database_admin'
  
  approved_patterns:
    - 'REBUILD_STATISTICS_*'  # Approved maintenance routine
```

---

## Detection Patterns

### CRITICAL (Always blocked)

```sql
-- ❌ DELETE without WHERE
DELETE FROM customers;

-- ❌ UPDATE without WHERE
UPDATE users SET status = 'active';

-- ❌ TRUNCATE
TRUNCATE TABLE audit_log;

-- ❌ Dynamic SQL with string concatenation
EXEC('SELECT * FROM ' + @table_name + ' WHERE id = ' + @id)
```

### HIGH (Blocked in strict mode)

```sql
-- ⚠️ Type conversion in WHERE (non-sargable)
WHERE CAST(date_string AS DATE) = '2026-05-18'

-- ⚠️ Correlated subquery
WHERE id IN (SELECT id FROM other_table WHERE x = t.x)

-- ⚠️ LIKE with leading wildcard
WHERE name LIKE '%value%'

-- ⚠️ NOT IN with subquery
WHERE id NOT IN (SELECT id FROM archived)
```

### MEDIUM (Informational)

```sql
-- ℹ️ SELECT * on large table
SELECT * FROM customers;

-- ℹ️ Hardcoded values
WHERE status = 'ACTIVE' AND date = '2026-05-18'

-- ℹ️ Deprecated function
SELECT GETDATE() instead of SYSDATETIME()
```

---

## Mutation Tracking

The `03_mutation_safeguard_monitor.sql` script creates audit tables:

```sql
-- Query recent mutations
SELECT 
    audit_timestamp,
    login_name,
    schema_name + '.' + table_name AS target_table,
    operation_type,
    row_count,
    CASE WHEN has_where_clause = 0 THEN '⚠️ NO WHERE' ELSE '✓ Has WHERE' END,
    risk_score,
    approval_status
FROM guardrail.mutation_audit
WHERE audit_timestamp > DATEADD(HOUR, -24, GETDATE())
ORDER BY audit_timestamp DESC;
```

**Approval Workflow:**
1. High-risk mutation recorded with `approval_status = 'PENDING'`
2. DBA reviews query and risk factors
3. Manual approval updates status to `'APPROVED'` or `'REJECTED'`
4. Application monitors approval status before executing mutation

---

## Integration Examples

### Application Middleware (Python)

```python
from db_guardrails import QueryGuard, QueryGuardConfig

config = QueryGuardConfig(
    max_execution_seconds=30,
    block_delete_without_where=True,
    block_update_without_where=True,
    block_truncate=True
)

guard = QueryGuard(config)

# In your ORM or query builder
if query_type == 'DELETE':
    allowed, reason, risk_score = guard.can_execute(query_sql, user='app_user')
    if not allowed:
        raise SecurityException(f'Query blocked: {reason}')
```

### Database Driver Proxy

Intercept all SQL at the connection layer:

```python
class GuardrailledConnection:
    def execute(self, query):
        guard = QueryGuard()
        allowed, reason, _ = guard.can_execute(query, user=self.user)
        if not allowed:
            self.log_violation(query, reason)
            raise Exception(f'Query rejected: {reason}')
        return self._real_connection.execute(query)
```

### Stored Procedure Wrapper

Wrap dangerous procs with validation:

```sql
CREATE PROCEDURE sp_SafeDelete
    @TableName SYSNAME,
    @WHERE NVARCHAR(MAX),
    @DryRun BIT = 1
AS
BEGIN
    -- Validate not empty WHERE
    IF NULLIF(@WHERE, '') IS NULL
        THROW 50001, 'WHERE clause required for SafeDelete', 1;
    
    -- Validate table exists
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = @TableName)
        THROW 50002, 'Table not found', 1;
    
    -- Preview rows to be deleted
    DECLARE @SQL NVARCHAR(MAX) = 'SELECT COUNT(*) FROM ' + @TableName + ' WHERE ' + @WHERE
    EXEC sp_executesql @SQL
    
    IF @DryRun = 0
    BEGIN
        SET @SQL = 'DELETE FROM ' + @TableName + ' WHERE ' + @WHERE
        EXEC sp_executesql @SQL
    END
END
```

---

## Monitoring & Alerts

### Slack Integration

Configure in `guardrails.yaml`:

```yaml
reporting:
  slack_webhook: "https://hooks.slack.com/services/YOUR/WEBHOOK"
  alert_thresholds:
    critical_count: 1
    high_count: 5
```

Guardrails will auto-post violations exceeding thresholds.

### Metrics

Track guardrails effectiveness over time:

```
db_guardrails_violations_total{severity="CRITICAL"} 5
db_guardrails_violations_total{severity="HIGH"} 42
db_guardrails_queries_blocked 12
db_guardrails_false_positives 2
```

---

## Troubleshooting

### False Positives

If guardrails are too strict, adjust `guardrails.yaml`:

```yaml
enforcement:
  level: 'moderate'  # Less aggressive

# Or whitelist specific patterns
whitelist:
  approved_patterns:
    - 'MAINTENANCE_DELETE_OLD_RECORDS'
```

### Bypassing Guardrails (Not Recommended)

For legitimate maintenance tasks:

```bash
# Git bypass (requires commit flag)
git commit --no-verify

# Application-level bypass (audit required)
guard = QueryGuard(config)
allowed, reason = guard.can_execute(query, user='dba_admin', override=True)
```

**Always log overrides and require change control approval.**

---

## Best Practices

1. **Start in `permissive` mode** — Log violations, learn patterns
2. **Graduate to `moderate`** — Block critical, alert on high
3. **Enable pre-commit hooks** — Catch issues before PR
4. **Require DBA approval** — For mutations on production tables
5. **Monitor false positives** — Adjust thresholds monthly
6. **Whitelist approved patterns** — Don't lower guardrails, add to whitelist
7. **Rotate credentials** — Guardrails service accounts should have read-only access to audit tables only

---

## Author

Author: Nitish Anand Srivastava
Last Updated: May 2026
