# Setup Instructions

## Prerequisites

- SQL Server 2016+ or Azure SQL Database
- Python 3.8+
- Git (for pre-commit hooks)
- Optional: Kubernetes, Ansible/AWX for orchestration

## Installation Steps

### 1. Clone Repository

```bash
git clone https://github.com/your-org/database-reliability-engineering.git
cd database-reliability-engineering
```

### 2. Install Python Tools

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r db-guardrails/requirements.txt
```

### 3. Initialize Database Audit Tables

```bash
# SQL Server
sqlcmd -S your-server -d your-database -E -i db-guardrails/scripts/03_mutation_safeguard_monitor.sql

# Azure SQL
sqlcmd -S your-server.database.windows.net -d your-database -U admin@server -P password -i db-guardrails/scripts/03_mutation_safeguard_monitor.sql
```

### 4. Setup Git Pre-Commit Hook

```bash
# Copy hook
cp db-guardrails/hooks/pre-commit-guardrails.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# Test
git commit --allow-empty -m "Test guardrails hook"
# Output: ✓ All guardrails checks passed
```

### 5. Configure GitHub Actions

```bash
# Copy workflow file
mkdir -p .github/workflows
cp db-guardrails/ci-cd/github_actions_workflow.yml .github/workflows/db-guardrails.yml

# Push to GitHub
git add .github/workflows/db-guardrails.yml
git commit -m "Add database guardrails workflow"
git push
```

### 6. Deploy to Kubernetes (Optional)

```bash
# Create namespace
kubectl create namespace database-ops

# Create secrets
kubectl create secret generic db-guardrails-secrets \
  --from-literal=sqlserver-host=sql-prod.contoso.com \
  --from-literal=sqlserver-database=OrderDB \
  --from-literal=sqlserver-user=guardrails_readonly \
  --from-literal=sqlserver-password=$(pass get db-guardrails-password) \
  -n database-ops

# Deploy CronJob
kubectl apply -f db-guardrails/ci-cd/k8s_guardrails_cronjob.yaml

# Verify
kubectl get cronjob -n database-ops
kubectl logs -n database-ops -l app=db-guardrails
```

### 7. Deploy with Ansible/AWX (Optional)

```bash
# Update inventory
ansible-inventory -i inventory/prod.ini --host db-prod-01

# Run playbook
ansible-playbook db-guardrails/ci-cd/awx_guardrails_playbook.yml \
  -i inventory/prod.ini \
  --ask-vault-pass
```

---

## Configuration

Copy `config/guardrails.yaml` and customize:

```yaml
# Enforcement level: strict, moderate, permissive
enforcement:
  level: 'moderate'

# Query timeouts
execution:
  max_execution_seconds: 30
  statement_timeout_ms: 30000

# Block specific operations
mutations:
  require_approval_for:
    - delete_operations
    - update_large_table
```

---

## Verification

### Test Static Analyzer

```bash
python scripts/sql_static_analyzer.py --stdin --strict <<EOF
DELETE FROM users;
EOF
```

Expected output:
```
[CRITICAL] Line 1: DELETE without WHERE clause
```

### Test Query Execution Guard

```bash
python scripts/query_execution_guard.py \
  --query "UPDATE products SET price = 99 WHERE category = 'Electronics'" \
  --user app_user --strict
```

### Run Database Checks

```bash
sqlcmd -S your-server -d your-database -E -i scripts/01_detect_ai_antipatterns.sql
```

---

## Troubleshooting

### Pre-commit hook not running

```bash
# Ensure hook is executable
chmod +x .git/hooks/pre-commit

# Verify it's called
git commit --no-verify -m "test"  # Should bypass hook
```

### Python module not found

```bash
# Reinstall dependencies
pip install --upgrade -r requirements.txt

# Verify installation
python -c "import pyodbc; print(pyodbc.version)"
```

### GitHub Actions failing

Check workflow logs:
```
Go to: GitHub repo → Actions → Database Guardrails → Logs
```

---

## Ongoing Maintenance

### Monthly Monitoring

1. Review false positives in guardrails alerts
2. Update `approved_patterns` whitelist
3. Check mutation audit log for anomalies
4. Adjust risk scoring thresholds

### Quarterly Review

1. Analyze guard effectiveness metrics
2. Update guardrails.yaml based on lessons learned
3. Train team on new AI-SQL risks
4. Rotate credentials for guardrails service account

---

## Support

- Issues: GitHub Issues
- Documentation: [GUARDRAILS_GUIDE.md](GUARDRAILS_GUIDE.md)
- Author: Nitish Anand Srivastava
