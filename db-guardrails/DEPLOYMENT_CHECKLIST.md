# Database Guardrails: Deployment & Validation Checklist

**Status:** Ready for Enterprise Deployment  
**Last Updated:** May 2026

---

## Pre-Deployment Checklist

### Environment Validation
- [ ] SQL Server 2016+ or Azure SQL Database confirmed
- [ ] Python 3.8+ installed (`python --version`)
- [ ] Git 2.9+ installed (`git --version`)
- [ ] Network connectivity to database confirmed
- [ ] Credentials configured and tested
- [ ] Write access to database (`CREATE TABLE` permission)
- [ ] Directory permissions: `.git/hooks/` writable

### Repository Preparation
- [ ] `db-guardrails/` directory in root
- [ ] Python scripts executable (`chmod +x scripts/*.py`)
- [ ] YAML files valid syntax
- [ ] `requirements.txt` dependencies listed

---

## Deployment Steps

### Phase 1: Database Setup (5 min)

```bash
# 1. Copy SQL scripts to local machine
cd db-guardrails/scripts

# 2. Test connection
sqlcmd -S your-server -d your-database -Q "SELECT @@VERSION"

# 3. Deploy mutation audit infrastructure
sqlcmd -S your-server -d your-database -i 03_mutation_safeguard_monitor.sql

# 4. Verify tables created
sqlcmd -S your-server -d your-database -Q "SELECT * FROM guardrail.mutation_audit" | head -5
```

**Validation:**
```sql
-- Check tables exist
SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_SCHEMA = 'guardrail' AND TABLE_NAME LIKE '%audit%';
-- Expected: mutation_audit, violation_log, approval_queue
```

- [ ] Audit tables created successfully
- [ ] Service account has INSERT/SELECT permissions
- [ ] No permission errors in deployment

### Phase 2: Pre-Commit Hook (5 min)

```bash
# 1. Copy hook to Git
cp db-guardrails/hooks/pre-commit-guardrails.sh .git/hooks/pre-commit

# 2. Make executable
chmod +x .git/hooks/pre-commit

# 3. Test hook
git commit --allow-empty -m "Test guardrails hook"

# Expected output:
# 🛡️ Running Database Guardrails Pre-Commit Checks...
# ✓ No SQL files to check
# ✓ All guardrails checks passed
```

**Validation:**
```bash
# Create a risky SQL file
echo "DELETE FROM users;" > test_risky.sql
git add test_risky.sql

# Try to commit (should fail)
git commit -m "Dangerous query"
# Expected: ❌ Pre-commit check failed

# Clean up
git reset HEAD test_risky.sql
rm test_risky.sql
```

- [ ] Pre-commit hook installed and executable
- [ ] Hook rejects risky SQL files
- [ ] Hook passes clean SQL files

### Phase 3: Python Tools (5 min)

```bash
# 1. Install dependencies
pip install -r db-guardrails/requirements.txt

# 2. Test static analyzer
python db-guardrails/scripts/sql_static_analyzer.py --stdin --strict <<EOF
DELETE FROM audit_log WHERE id = 123;
EOF
# Expected output: Warnings but exits 0 (has WHERE clause)

# 3. Test with risky SQL
python db-guardrails/scripts/sql_static_analyzer.py --stdin --strict <<EOF
DELETE FROM users;
EOF
# Expected output: CRITICAL violation, exit code 1
```

**Validation:**
- [ ] sql_static_analyzer.py runs without errors
- [ ] Detects DELETE without WHERE
- [ ] Passes DELETE with WHERE clause
- [ ] Exit codes correct (0 for pass, 1 for fail)

### Phase 4: CI/CD Integration (GitHub Actions)

```bash
# 1. Create workflow directory
mkdir -p .github/workflows

# 2. Copy workflow file
cp db-guardrails/ci-cd/github_actions_workflow.yml \
   .github/workflows/db-guardrails.yml

# 3. Commit and push
git add .github/workflows/db-guardrails.yml
git commit -m "Add database guardrails CI workflow"
git push

# 4. Create test PR
git checkout -b test/guardrails-ci
echo "-- Safe query" > test.sql
echo "SELECT * FROM users WHERE id = 1;" >> test.sql
git add test.sql
git commit -m "Add test query"
git push origin test/guardrails-ci
```

**Validation (in GitHub):**
- [ ] Go to repo → Pull requests → Create new PR
- [ ] Check runs appear under "Database Guardrails Check"
- [ ] PR status shows checks passed ✓
- [ ] Merge button enabled for clean PRs

**Test with risky SQL:**
```bash
git checkout -b test/risky-sql
echo "DELETE FROM users;" > risky.sql
git add risky.sql
git commit -m "Risky query"
git push origin test/risky-sql
```

- [ ] PR created and checks run
- [ ] Checks show failures ❌
- [ ] Merge blocked until violations fixed
- [ ] Violations clearly documented in PR comments

### Phase 5: Kubernetes Deployment (Optional - 15 min)

```bash
# 1. Create namespace
kubectl create namespace database-ops

# 2. Create secret with DB credentials
kubectl create secret generic db-guardrails-secrets \
  --from-literal=sqlserver-host=sql-prod.contoso.com \
  --from-literal=sqlserver-database=OrderDB \
  --from-literal=sqlserver-user=readonly_guardrails \
  --from-literal=sqlserver-password=$(pass get db/guardrails) \
  -n database-ops

# 3. Deploy CronJob
kubectl apply -f db-guardrails/ci-cd/k8s_guardrails_cronjob.yaml

# 4. Verify deployment
kubectl get cronjob -n database-ops
# Expected: db-guardrails-audit with schedule "0 2 * * *"

# 5. Test manual job
kubectl create job --from=cronjob/db-guardrails-audit test-run -n database-ops

# 6. Check logs
kubectl logs -n database-ops -l app=db-guardrails --tail=50
```

**Validation:**
- [ ] Namespace created
- [ ] Secret created with all required fields
- [ ] CronJob deployed successfully
- [ ] Manual test job runs without errors
- [ ] No permission errors in logs

### Phase 6: Ansible/AWX Deployment (Optional - 15 min)

```bash
# 1. Prepare inventory
cat > inventory/prod.ini <<EOF
[database_servers]
db-prod-01 ansible_host=prod-db-01.contoso.com
db-prod-02 ansible_host=prod-db-02.contoso.com
EOF

# 2. Test connectivity
ansible -i inventory/prod.ini all -m ping

# 3. Deploy guardrails
ansible-playbook db-guardrails/ci-cd/awx_guardrails_playbook.yml \
  -i inventory/prod.ini \
  -v

# 4. Verify deployment
ansible -i inventory/prod.ini all -m shell \
  -a "ls -la /opt/db-guardrails/"
```

**Validation:**
- [ ] Ansible connectivity verified (ping successful)
- [ ] Playbook executes without errors
- [ ] Guardrails directory created on targets
- [ ] Cron jobs configured
- [ ] Log directory created with correct permissions

---

## Configuration Validation

### guardrails.yaml Review

```yaml
# ✓ Verify enforcement level matches your risk tolerance
enforcement:
  level: 'moderate'  # Should be: strict/moderate/permissive

# ✓ Verify query timeouts are reasonable
execution:
  max_execution_seconds: 30

# ✓ Verify mutation safeguards are enabled
mutations:
  block_delete_without_where: true
  block_update_without_where: true
  block_truncate: true

# ✓ Verify approvals required for high-risk operations
  require_approval_for:
    - delete_operations
    - update_large_table

# ✓ Verify alert thresholds
reporting:
  alert_thresholds:
    critical_count: 1
    high_count: 5
```

**Checklist:**
- [ ] Enforcement level appropriate for environment
- [ ] Timeouts prevent runaway queries
- [ ] Mutations properly restricted
- [ ] Approval workflow configured
- [ ] Alert recipients configured

---

## Functional Testing

### Test 1: DELETE Without WHERE

```bash
# Create test file
cat > test_delete.sql <<EOF
DELETE FROM test_table;
EOF

# Test static analyzer
python db-guardrails/scripts/sql_static_analyzer.py \
  --file test_delete.sql --strict

# Expected: Exit code 1, CRITICAL violation
```

✓ Result: Blocked

### Test 2: DELETE With WHERE

```bash
# Create test file
cat > test_delete_safe.sql <<EOF
DELETE FROM test_table 
WHERE id = 123 AND status = 'archived';
EOF

# Test static analyzer
python db-guardrails/scripts/sql_static_analyzer.py \
  --file test_delete_safe.sql --strict

# Expected: Exit code 0, passed
```

✓ Result: Passed

### Test 3: SQL Injection Pattern

```bash
# Create test file
cat > test_injection.sql <<EOF
DECLARE @table NVARCHAR(MAX) = 'users'
EXEC('SELECT * FROM ' + @table)
EOF

# Test static analyzer
python db-guardrails/scripts/sql_static_analyzer.py \
  --file test_injection.sql --strict

# Expected: Exit code 1, SQL injection detected
```

✓ Result: Blocked

### Test 4: Correlated Subquery

```bash
# Create test file
cat > test_correlated.sql <<EOF
SELECT * FROM customers c
WHERE c.id IN (SELECT customer_id FROM orders o WHERE o.date > c.last_order)
EOF

# Test static analyzer
python db-guardrails/scripts/sql_static_analyzer.py \
  --file test_correlated.sql --strict

# Expected: HIGH severity warning
```

✓ Result: Flagged for review

---

## Monitoring Setup

### Enable Slack Alerts

```yaml
# In guardrails.yaml
reporting:
  slack_webhook: "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX"
```

**Test:**
```bash
# Generate test violation
python scripts/sql_static_analyzer.py --stdin --strict <<EOF
DELETE FROM users;
EOF

# Check Slack channel for alert
```

✓ Alert posted to Slack

### Enable Email Alerts

```yaml
# In guardrails.yaml
reporting:
  email_recipients:
    - dba-team@company.local
    - security-team@company.local
```

**Test:**
```bash
# Check email inbox for test alert
```

✓ Email received

### Query Audit Tables

```sql
-- Check recent mutations
SELECT TOP 10 
    audit_timestamp,
    login_name,
    operation_type,
    row_count,
    has_where_clause,
    risk_score
FROM guardrail.mutation_audit
ORDER BY audit_timestamp DESC;

-- Check pending approvals
SELECT * FROM guardrail.mutation_approvals 
WHERE approval_status = 'PENDING';

-- Check recent violations
SELECT TOP 20
    audit_timestamp,
    violation_type,
    severity,
    risk_score,
    action_taken
FROM guardrail.violations
ORDER BY audit_timestamp DESC;
```

---

## Performance Validation

### Analyzer Performance

```bash
# Generate large SQL file
python -c "
import random
queries = []
for i in range(100):
    queries.append(f'SELECT * FROM table_{i}')
print('\\n'.join(queries))
" > large_query.sql

# Test performance
time python db-guardrails/scripts/sql_static_analyzer.py --file large_query.sql

# Expected: < 1 second
```

✓ Performance acceptable

### Database Audit Tables

```sql
-- Check index performance
SELECT object_name, index_name FROM sys.indexes 
WHERE object_name LIKE 'mutation_audit';

-- Monitor table size
SELECT 
    object_name(i.object_id) AS table_name,
    sum(p.rows) AS row_count,
    sum(a.total_pages) * 8 / 1024 / 1024 AS total_mb
FROM sys.indexes i
JOIN sys.partitions p ON i.object_id = p.object_id
JOIN sys.allocation_units a ON p.hobt_id = a.container_id
WHERE object_name(i.object_id) = 'mutation_audit'
GROUP BY i.object_id;
```

---

## Post-Deployment Tasks

### Week 1: Baseline
- [ ] Run daily audits - capture violations
- [ ] Review false positives
- [ ] Establish baseline metrics
- [ ] Document common patterns

### Week 2-4: Adjustment
- [ ] Tune enforcement level based on false positives
- [ ] Update whitelist for approved patterns
- [ ] Train development team on violations
- [ ] Establish DBA review process

### Monthly: Monitoring
- [ ] Review effectiveness metrics
- [ ] Check false positive rate (<5% target)
- [ ] Adjust risk thresholds
- [ ] Update policies based on lessons learned

---

## Rollback Plan

If guardrails cause critical issues:

### Pre-Commit Hook Bypass
```bash
# Temporary bypass (not recommended)
git commit --no-verify

# Or remove hook entirely
rm .git/hooks/pre-commit
```

### Switch to Permissive Mode
```yaml
# In guardrails.yaml
enforcement:
  level: 'permissive'  # Log only, don't block
```

### Disable CI/CD Checks
```bash
# Remove workflow
rm .github/workflows/db-guardrails.yml

# Or comment out jobs in workflow file
```

### Disable Kubernetes Monitoring
```bash
kubectl delete cronjob db-guardrails-audit -n database-ops
```

---

## Success Criteria

After 30 days, verify:

- [ ] No critical violations in production
- [ ] <5% false positive rate
- [ ] All developers trained on guardrails
- [ ] DBA approval workflow established
- [ ] Monitoring alerts functioning
- [ ] Audit trail complete and accurate
- [ ] No risky queries reaching production

---

## Emergency Contacts

- **DB Guardrails Author**: Nitish Anand Srivastava
- **DBA On-Call**: [Contact]
- **Security Team**: [Contact]
- **DevOps Team**: [Contact]

---

## Documentation References

- [GUARDRAILS_GUIDE.md](GUARDRAILS_GUIDE.md) — Feature guide
- [SETUP_INSTRUCTIONS.md](SETUP_INSTRUCTIONS.md) — Installation
- [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) — Overview
- [integration_examples.py](examples/integration_examples.py) — Code samples

---

**Deployment Ready: ✓**  
**Status: Production Grade**  
**Last Updated: May 2026**
