# Database Guardrails: Complete Package

A production-grade, multi-layer defense system protecting SQL Server and Azure SQL databases from AI-generated SQL risks.

**Version:** 1.0  
**Status:** Ready for Production  
**Last Updated:** May 2026

---

## 📋 Table of Contents

1. [Quick Start](#quick-start)
2. [Architecture](#architecture)
3. [Components](#components)
4. [Getting Started](#getting-started)
5. [Usage Examples](#usage-examples)
6. [Configuration](#configuration)
7. [Monitoring & Alerts](#monitoring--alerts)
8. [Best Practices](#best-practices)
9. [Support](#support)

---

## 🚀 Quick Start

### 1-Minute Setup

```bash
# Clone repo
git clone https://github.com/your-org/database-reliability-engineering.git
cd database-reliability-engineering

# Install tools
pip install -r db-guardrails/requirements.txt

# Run database initialization
sqlcmd -S your-server -d your-db -i db-guardrails/scripts/03_mutation_safeguard_monitor.sql

# Install pre-commit hook
cp db-guardrails/hooks/pre-commit-guardrails.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# Test
git commit --allow-empty -m "Test guardrails"
```

**That's it!** Every SQL commit is now protected.

---

## 🏗️ Architecture

### Defense Layers

```
┌─────────────────────────────────────────────────────────┐
│  Developer Workstation                                  │
├─────────────────────────────────────────────────────────┤
│  Git Pre-Commit Hook (Blocks risky SQL before commit)  │
├─────────────────────────────────────────────────────────┤
│  GitHub/GitLab (CI/CD Pipeline)                        │
├─────────────────────────────────────────────────────────┤
│  Pull Request Checks (Automatic code review)           │
├─────────────────────────────────────────────────────────┤
│  Static Analysis (Before deployment)                   │
├─────────────────────────────────────────────────────────┤
│  Database Layer (Runtime guards + audit trails)        │
├─────────────────────────────────────────────────────────┤
│  Kubernetes/Monitoring (Continuous compliance)         │
└─────────────────────────────────────────────────────────┘
```

### What It Protects

| Risk | Detection | Enforcement |
|------|-----------|-------------|
| **DELETE without WHERE** | ✓ SQL Parser | ✓ Pre-commit Hook, CI/CD, Runtime |
| **UPDATE without WHERE** | ✓ Pattern Matching | ✓ Pre-commit Hook, CI/CD, Runtime |
| **TRUNCATE Operations** | ✓ AST Analysis | ✓ Pre-commit Hook, CI/CD, Runtime |
| **SQL Injection** | ✓ Dynamic SQL Detection | ✓ Pre-commit Hook, CI/CD, Runtime |
| **Long-Running Queries** | ✓ Query Plan Analysis | ✓ Timeout Enforcement |
| **Missing Indexes** | ✓ Statistics Analysis | ✓ Warnings |
| **Correlated Subqueries** | ✓ Pattern Detection | ✓ Risk Scoring |
| **Type Conversions** | ✓ Expression Analysis | ✓ Risk Scoring |

---

## 📦 Components

### SQL Scripts (Database-Level)

| Script | Purpose | Frequency |
|--------|---------|-----------|
| `01_detect_ai_antipatterns.sql` | Scan stored procedures for risky patterns | Daily |
| `02_query_complexity_risk_scoring.sql` | Analyze query plans, identify slow queries | Hourly |
| `03_mutation_safeguard_monitor.sql` | Audit all INSERT/UPDATE/DELETE operations | Real-time |
| `04_transaction_lock_guard.sql` | Monitor blocking chains, long transactions | Continuous |

### Python Tools

| Tool | Purpose | Usage |
|------|---------|-------|
| `sql_static_analyzer.py` | Pre-deployment static analysis | `python sql_static_analyzer.py --file query.sql` |
| `query_execution_guard.py` | Runtime query protection | Application middleware |

### CI/CD Integration

| File | Platform | Purpose |
|------|----------|---------|
| `github_actions_workflow.yml` | GitHub Actions | Automated PR checks |
| `pre-commit-guardrails.sh` | Git | Local commit-time validation |
| `k8s_guardrails_cronjob.yaml` | Kubernetes | Periodic database audits |
| `awx_guardrails_playbook.yml` | Ansible/AWX | Infrastructure deployment |

### Configuration

| File | Purpose |
|------|---------|
| `guardrails.yaml` | Centralized policy, thresholds, enforcement levels |

---

## 🔧 Getting Started

### Prerequisites

- SQL Server 2016+ or Azure SQL Database
- Python 3.8+
- Git 2.9+ (for pre-commit hooks)
- Optional: Kubernetes, Ansible/AWX

### Installation

See [SETUP_INSTRUCTIONS.md](SETUP_INSTRUCTIONS.md) for detailed setup.

```bash
# 1. Clone repo
git clone https://github.com/your-org/database-reliability-engineering.git

# 2. Install Python dependencies
cd db-guardrails
pip install -r requirements.txt

# 3. Initialize database tables
sqlcmd -S server -d database -i scripts/03_mutation_safeguard_monitor.sql

# 4. Setup pre-commit hook
cp hooks/pre-commit-guardrails.sh ../.git/hooks/pre-commit

# 5. Deploy to CI/CD
cp ci-cd/github_actions_workflow.yml ../.github/workflows/

# 6. Deploy to Kubernetes (optional)
kubectl apply -f ci-cd/k8s_guardrails_cronjob.yaml
```

---

## 💡 Usage Examples

### Example 1: Pre-Commit Protection

```bash
# Developer writes risky SQL
echo "DELETE FROM users;" > migration.sql

# Try to commit
git add migration.sql
git commit -m "Delete users"

# ❌ Pre-commit check failed: 1 file(s) have critical issues
# [CRITICAL] DELETE without WHERE clause

# Fix the query
echo "DELETE FROM users WHERE created_at < '2020-01-01';" > migration.sql
git add migration.sql
git commit -m "Delete old users"

# ✓ All guardrails checks passed
# [main a1b2c3d] Delete old users
```

### Example 2: CI/CD Pipeline Check

Every PR with SQL files automatically gets analyzed:

```yaml
name: Database Guardrails

on: [pull_request]

jobs:
  guardrails:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v4
      - run: python db-guardrails/scripts/sql_static_analyzer.py --file query.sql --strict
```

**Result:** PR blocked until violations are fixed.

### Example 3: Application Middleware Protection

```python
from db_guardrails import QueryGuard

# In your ORM or database layer
guard = QueryGuard(config)

if query_type == 'DELETE':
    allowed, reason, risk_score = guard.can_execute(query, user=user)
    if not allowed:
        raise SecurityException(f'Blocked: {reason}')
    
    # Log mutation
    audit.log_mutation(query, user, risk_score)
    
    # Execute with timeout
    result = execute_with_timeout(query, 30)
```

### Example 4: Mutation Approval Workflow

High-risk mutations require DBA approval:

```python
# Developer submits query
result = workflow.submit_mutation(
    query="DELETE FROM archive WHERE date < '2020-01-01'",
    reason="Archiving old records",
    requested_by="app_user"
)

# Result: status = PENDING_APPROVAL
# DBA is notified and must review

# DBA approves
workflow.approve_mutation(approval_id, approved_by='dba_user')

# Query executes and is audited
```

See [integration_examples.py](examples/integration_examples.py) for more examples.

---

## ⚙️ Configuration

### Enforcement Levels

```yaml
enforcement:
  level: 'moderate'  # strict, moderate, permissive
```

- **strict**: Block CRITICAL + HIGH severity violations
- **moderate**: Block CRITICAL; alert on HIGH
- **permissive**: Log violations; never block

### Risk Thresholds

```yaml
risk_scoring:
  delete_without_where: 100      # Critical
  update_without_where: 100      # Critical
  truncate: 100                  # Critical
  correlated_subquery_risk: 20   # High
  missing_indexes: 10             # Medium
```

### Query Limits

```yaml
execution:
  max_execution_seconds: 30      # Kill queries exceeding this
  max_memory_mb: 1024            # Memory limit
  max_row_output: 1000000        # Result set limit
  statement_timeout_ms: 30000    # SQL Server timeout
```

---

## 📊 Monitoring & Alerts

### Guardrails Dashboard

Query the audit tables to understand violations:

```sql
-- Recent violations
SELECT TOP 20 
    audit_timestamp,
    violation_type,
    risk_score,
    query_summary,
    action_taken
FROM guardrail.violations
ORDER BY audit_timestamp DESC;

-- High-risk users
SELECT 
    user_id,
    COUNT(*) AS violation_count,
    AVG(risk_score) AS avg_risk
FROM guardrail.violations
WHERE audit_timestamp > DATEADD(DAY, -30, GETDATE())
GROUP BY user_id
ORDER BY avg_risk DESC;
```

### Slack Integration

Violations exceeding thresholds automatically post to Slack:

```yaml
reporting:
  slack_webhook: "https://hooks.slack.com/services/YOUR/WEBHOOK"
  alert_thresholds:
    critical_count: 1
    high_count: 5
```

### Metrics

Track guardrails effectiveness:

```
db_guardrails_violations_total{severity="CRITICAL"} 5
db_guardrails_violations_total{severity="HIGH"} 42
db_guardrails_queries_blocked 12
db_guardrails_false_positives 2
```

---

## ✅ Best Practices

1. **Start in `permissive` mode** — Learn your patterns first
2. **Graduate to `moderate`** — Block critical, warn high
3. **Enable pre-commit hooks** — Catch issues before PR
4. **Require DBA approval** — For production mutations
5. **Monitor false positives** — Adjust thresholds monthly
6. **Whitelist approved patterns** — Don't lower guardrails
7. **Rotate credentials** — Guardrails service accounts should be read-only

---

## 📚 Documentation

- [GUARDRAILS_GUIDE.md](GUARDRAILS_GUIDE.md) — Complete feature guide
- [SETUP_INSTRUCTIONS.md](SETUP_INSTRUCTIONS.md) — Installation and deployment
- [examples/integration_examples.py](examples/integration_examples.py) — Code samples
- [tests/test_guardrails.py](tests/test_guardrails.py) — Test suite

---

## 🐛 Troubleshooting

### Pre-commit hook not running

```bash
# Ensure hook is executable
chmod +x .git/hooks/pre-commit

# Test
git commit --allow-empty -m "test"
```

### GitHub Actions failing

Check workflow logs in GitHub Actions tab.

### False positives

Adjust `guardrails.yaml`:
- Lower `risk_scoring` thresholds
- Add patterns to `whitelist.approved_patterns`
- Switch to `permissive` mode

---

## 👥 Support

- **Issues**: GitHub Issues
- **Documentation**: See docs/ folder
- **Questions**: Ask in #database-reliability channel

---

## 📄 License

MIT License - See LICENSE file

---

## 🙏 Contributors

- Nitish Anand Srivastava (Author)
- Database Reliability Engineering Team

---

## 🎯 Roadmap

- [ ] PostgreSQL support
- [ ] MySQL/MariaDB support
- [ ] Machine learning-based anomaly detection
- [ ] Advanced visualization dashboard
- [ ] Kubernetes Operator
- [ ] Terraform module

---

**Last Updated:** May 2026  
**Version:** 1.0 (Production Ready)
